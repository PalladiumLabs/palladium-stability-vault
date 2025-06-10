pragma solidity ^0.8.0;

import "@openzeppelin/token/ERC20/IERC20.sol";
import "@openzeppelin/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/token/ERC20/utils/SafeERC20.sol";
import "../../lib/openzeppelin-contracts-upgradeable/contracts/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/proxy/utils/UUPSUpgradeable.sol";
import "./interfaces/IV3SwapRouter.sol";
import "./common/FeeManager.sol";
import "./interfaces/IV3SwapRouter.sol";
import "./interfaces/IStabilityPool.sol";
import "./interfaces/IPriceFeed.sol";
import "./interfaces/ITroveManagerOperations.sol";
import "./interfaces/IPancakeV3Pool.sol";
import "./interfaces/IDolomiteMargin.sol";
import "./interfaces/IDepositWithdrawalRouter.sol";

struct VaultConfig {
    address depositToken;
    address baseToken;
    address stabilityPool;
    address priceFeed;
}

struct CommonAddress {
    address vault;
    address manager;
    address router;
    address vManager;
    address doloM;
    address doloRouter;
    uint256 allocation; // allocation in basis points (1000 = 10%)
    uint256 withdrawFee;
    uint256 withdrawFeeDecimals;
    uint256 slippage;
    uint256 slippageDecimals;
}

contract StabilityVault is Initializable, UUPSUpgradeable, ReentrancyGuardUpgradeable, FeeManager {
    address public depositToken; // deposit token (PUSD)
    address public baseToken; // base token to swap all asset before swapping to depositToken
    address[] public collateralAssets;

    address public stabilityPool;
    address public priceFeed;
    address public troveManager;

    address public doloM;
    address public doloRouter;

    uint256 public allocation;

    mapping(address => mapping(address => address)) public swapPools;

    mapping(address => address) public oracles;

    function init(VaultConfig memory _configs, CommonAddress memory _commonAddress) public initializer {
        __Ownable2Step_init();
        __ReentrancyGuard_init();
        __Pausable_init();
        depositToken = _configs.depositToken;
        baseToken = _configs.baseToken;
        stabilityPool = _configs.stabilityPool;
        priceFeed = _configs.priceFeed;

        vault = _commonAddress.vault;
        manager = _commonAddress.manager;
        router = _commonAddress.router;
        withdrawFee = _commonAddress.withdrawFee;
        withdrawFeeDecimals = _commonAddress.withdrawFeeDecimals;
        slippage = _commonAddress.slippage;
        slippageDecimals = _commonAddress.slippageDecimals;
        troveManager = _commonAddress.vManager;
        doloM = _commonAddress.doloM;
        doloRouter = _commonAddress.doloRouter;
        allocation = _commonAddress.allocation;
        _giveAllowances();
    }

    function addCollateralAsset(address _asset, address _oracle) public {
        onlyManager();
        collateralAssets.push(_asset);
        oracles[_asset] = _oracle;
        _giveAllowances(_asset);
    }

    function deposit() public whenNotPaused {
        onlyVault();
        _deposit();
    }

    function _deposit() internal {
        _provideToSP();
        onYield();
    }

    function withdraw(uint256 _amount) public nonReentrant {
        onlyVault();
        uint256 currentBal = IERC20(depositToken).balanceOf(address(this));
        if (_amount <= currentBal) {
            IERC20(depositToken).transfer(vault, _amount);
        } else {
            harvest();
            uint256 fromSp = allocation * _amount / 1000;
            IStabilityPool(stabilityPool).withdrawFromSP(fromSp, collateralAssets);
            offYield(_amount - fromSp);
            IERC20(depositToken).transfer(vault, _amount);
        }
    }

    function compoundGains() public {
        onlyManager();

        for (uint256 i = 0; i < collateralAssets.length; i++) {
            uint256 gainBalance = IERC20(collateralAssets[i]).balanceOf(address(this));
            if (gainBalance > 0) {
                _swapV3In(collateralAssets[i], baseToken, gainBalance);
            }
        }

        uint256 baseBalance = IERC20(baseToken).balanceOf(address(this));

        if (baseBalance > 0) {
            _swapV3In(baseToken, depositToken, baseBalance);
            _provideToSP();
            onYield();
        }
    }

    function closePostion() external {
        onlyManager();
        _closePostion();
    }

    function _closePostion() internal {
        uint256 amount = balanceOfSp();
        IStabilityPool(stabilityPool).withdrawFromSP(amount, collateralAssets);
        uint256 balYield = balanceOfYield();
        offYield(balYield);
    }

    function rebalance() external {
        onlyManager();
        _closePostion();
        _deposit();
    }

    function _provideToSP() internal {
        uint256 _amount = IERC20(depositToken).balanceOf(address(this));
        uint256 inSp = allocation * _amount/1000;
        IStabilityPool(stabilityPool).provideToSP(inSp, collateralAssets);
    }

    function withdrawFromSP(uint256 _amount) internal {
        IStabilityPool(stabilityPool).withdrawFromSP(_amount, collateralAssets);
    }

    function addPool(address _collateralAsset, address _baseToken, address _pool) external returns (bool) {
        onlyManager();
        swapPools[_collateralAsset][_baseToken] = _pool;
        swapPools[_baseToken][_collateralAsset] = _pool;
        return true;
    }

    function addOracle(address _asset, address _oracle) external {
        onlyManager();
        oracles[_asset] = _oracle;
    }

    function liquidate(address _asset, uint256 _n) public {
        IVesselManagerOperations(troveManager).liquidateVessels(_asset, _n);
    }

    function onYield() internal {
        uint256 amount = IERC20(depositToken).balanceOf(address(this));
        uint256 mrktID = IDolomiteMargin(doloM).getMarketIdByTokenAddress(depositToken);
        IDepositWithdrawalRouter(doloRouter).depositWei(0, 0, mrktID, amount, IDepositWithdrawalRouter.EventFlag.None);
    }

    function offYield(uint256 _amount) internal {
        uint256 mrktID = IDolomiteMargin(doloM).getMarketIdByTokenAddress(depositToken);

        IDepositWithdrawalRouter(doloRouter).withdrawWei(
            0, 0, mrktID, _amount, AccountBalanceLib.BalanceCheckFlag.None
        );
    }

    function harvest() public {
        IStabilityPool(stabilityPool).withdrawFromSP(0, collateralAssets);
        for (uint256 i = 0; i < collateralAssets.length; i++) {
            uint256 assetBal = IERC20(collateralAssets[i]).balanceOf(address(this));
            if (assetBal > 0) {
                _swapV3In(collateralAssets[i], baseToken, assetBal);
            }
        }
        uint256 baseBal = IERC20(baseToken).balanceOf(address(this));
        if (baseBal > 0) {
            _swapV3In(baseToken, depositToken, baseBal);
            _deposit();
        }
    }


    function setAllo(uint256 _newAllo) external returns(uint256) {
        onlyManager();
        allocation = _newAllo;
        return allocation;
    }

    function _swapV3In(address tokenIn, address tokenOut, uint256 amountIn) internal returns (uint256 amountOut) {
        if (tokenIn != tokenOut) {
            address pool = swapPools[tokenIn][tokenOut];
            uint24 fee = IPancakeV3Pool(pool).fee();
            uint256 amountBMax = tokenAToTokenBConversion(tokenIn, tokenOut, amountIn);
            uint256 amountBMin = amountBMax * slippage / slippageDecimals;
            amountOut = IV3SwapRouter(router).exactInputSingle(
                IV3SwapRouter.ExactInputSingleParams(tokenIn, tokenOut, fee, address(this), amountIn, amountBMin, 0)
            );
        }
    }

    function tokenToUSD(address _asset, uint256 _amount) public view returns (uint256) {
        address oracle = oracles[_asset];
        (, int256 answer,,,) = ChainlinkAggregatorV3Interface(oracle).latestRoundData();
        uint256 decimals = ChainlinkAggregatorV3Interface(oracle).decimals();
        return (uint256(answer) * _amount) / (10 ** decimals);
    }

    function balanceOf() public view returns (uint256) {
        return balanceOfSp() + balaceOfGains() + balanceOfDepositToken() + balanceOfYield();
    }

    function balanceOfSp() public view returns (uint256) {
        return IStabilityPool(stabilityPool).getCompoundedDebtTokenDeposits(address(this));
    }

    function balanceOfDepositToken() public view returns (uint256) {
        return IERC20(depositToken).balanceOf(address(this));
    }

    function balaceOfGains() public view returns (uint256) {
        (address[] memory assets, uint256[] memory gains) =
            IStabilityPool(stabilityPool).getDepositorGains(address(this), collateralAssets);
        uint256 amount;
        for (uint256 i = 0; i < gains.length; i++) {
            amount = tokenToUSD(assets[i], gains[i]) + amount;
        }

        return amount;
    }

    function balanceOfYield() public view returns (uint256) {
        uint256 mrktID = IDolomiteMargin(doloM).getMarketIdByTokenAddress(depositToken);
        Account.Info memory account = Account.Info({owner: address(this), number: 0});

        Types.Wei memory myWei = IDolomiteMargin(doloM).getAccountWei(account, mrktID);
        return myWei.value;
    }

    function tokenAToTokenBConversion(address _tokenA, address _tokenB, uint256 amountA)
        public
        view
        returns (uint256)
    {
        uint256 tokenADecimal = IERC20Metadata(_tokenA).decimals();
        uint256 tokenBDecimal = IERC20Metadata(_tokenB).decimals();

        (uint256 tokenAPrice, uint256 tokenAOracleDecimal) = getPrice(_tokenA);
        (uint256 tokenBPrice, uint256 tokenBOracleDecimal) = getPrice(_tokenB);

        uint256 amountAInUSD = ((10 ** tokenADecimal) * (10 ** tokenAOracleDecimal)) / tokenAPrice;

        uint256 amountBInUSD = ((10 ** tokenBDecimal) * (10 ** tokenBOracleDecimal)) / tokenBPrice;

        uint256 amountBInA = (amountBInUSD * (10 ** tokenADecimal)) / amountAInUSD;

        return (amountBInA * amountA) / 10 ** tokenADecimal;
    }

    function getPrice(address _asset) public view returns (uint256, uint256) {
        address oracle = oracles[_asset];
        (, int256 answer,,,) = ChainlinkAggregatorV3Interface(oracle).latestRoundData();
        uint256 decimals = ChainlinkAggregatorV3Interface(oracle).decimals();
        return (uint256(answer), decimals);
    }

    function incaseTokenGetStuck(address _token , address _receiver) public {
        onlyManager();
        require(_token != depositToken, "Cannot withdraw deposit token");
        require(_token != baseToken, "Cannot withdraw base token");
        require(_token != address(0), "Invalid token address");

        uint256 balance = IERC20(_token).balanceOf(address(this));
        require(balance > 0, "No balance to withdraw");
        IERC20(_token).transfer(_receiver, balance);
    }

    function pause() public {
        onlyManager();
        _pause();
    }

    function unpause() public {
        onlyManager();
        _unpause();
    }

    function _giveAllowances() internal virtual {
        IERC20(depositToken).approve(stabilityPool, type(uint256).max);
        IERC20(depositToken).approve(router, type(uint256).max);
        IERC20(depositToken).approve(doloRouter, type(uint256).max);
        IERC20(baseToken).approve(doloRouter,type(uint256).max);
        IERC20(baseToken).approve(router, type(uint256).max);
     
        for (uint256 i = 0; i < collateralAssets.length; i++) {
            IERC20(collateralAssets[i]).approve(stabilityPool, type(uint256).max);
            IERC20(collateralAssets[i]).approve(router, type(uint256).max);
            IERC20(collateralAssets[i]).approve(doloRouter, type(uint256).max);
        }
    }

    function _giveAllowances(address _asset) internal virtual {
        IERC20(_asset).approve(stabilityPool, type(uint256).max);
        IERC20(_asset).approve(router, type(uint256).max);
        IERC20(_asset).approve(doloRouter, type(uint256).max);
    }

    function _removeAllowances() internal virtual {
        IERC20(depositToken).approve(stabilityPool, 0);
        IERC20(depositToken).approve(router, 0);
        IERC20(depositToken).approve(doloRouter, 0);
        IERC20(baseToken).approve(router, 0);
       
        for (uint256 i = 0; i < collateralAssets.length; i++) {
            IERC20(collateralAssets[i]).approve(stabilityPool, 0);
            IERC20(collateralAssets[i]).approve(router, 0);
            IERC20(collateralAssets[i]).approve(doloRouter, 0);
        }
    }

    function _removeAllowances(address _asset) internal virtual {
        IERC20(_asset).approve(stabilityPool, 0);
        IERC20(_asset).approve(router, 0);
        IERC20(_asset).approve(doloRouter, 0);
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}
}
