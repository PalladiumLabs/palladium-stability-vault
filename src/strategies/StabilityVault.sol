// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

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
    using SafeERC20 for IERC20;

    address public depositToken; // deposit token (PUSD)
    address public baseToken; // base token to swap all asset before swapping to depositToken
    address[] public collateralAssets;

    address public stabilityPool;
    address public priceFeed;
    address public troveManager;

    address public doloM;
    address public doloRouter;

    uint256 public allocation;

    mapping(address => uint256) public oracleTimeout;

    mapping(address => mapping(address => address)) public swapPools;

    mapping(address => address) public oracles;

    uint256 public constant PERCENTAGE_BASE = 1000;

    //events
    event CollateralAdded(address asset, address oracle);
    event WithdrawStrat(uint256 _amount, uint256 _fee);
    event PostionClosed(uint256 fromSp, uint256 fromYield);
    event PoolAdded(address _collateral, address _baseToken, address _pool);
    event OracleAdded(address _asset, address _oracle);
    event newAllo(uint256 _newAllocation);
    event SentFunds(address _token, address _receiver, uint256 _amount);
    event Harvest(address _token,uint256 _amount);

    //cutome errors
    error FeedPriceNotPositive(int256);
    error FeedHeartbeatExceeded(uint256, uint256, uint256);
    error ExceedsMax(uint256, uint256);
    error ZeroBalance();
    error SystemToken();
    error ZeroAddress();

    constructor() {
        _disableInitializers();
    }

    function init(VaultConfig memory _configs, CommonAddress memory _commonAddress) public initializer {
        __Ownable2Step_init();
        __Ownable_init(msg.sender);
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

    function addCollateralAsset(address _asset, address _oracle, uint256 _timeout) public {
        onlyManager();
        collateralAssets.push(_asset);
        oracles[_asset] = _oracle;
        oracleTimeout[_oracle] = _timeout;
        _giveAllowances(_asset);
        emit CollateralAdded(_asset, _oracle);
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
            IERC20(depositToken).safeTransfer(vault, _amount);
        } else {
            harvest();
            uint256 fromSp = (allocation * _amount) / PERCENTAGE_BASE;
            IStabilityPool(stabilityPool).withdrawFromSP(fromSp, collateralAssets);
            offYield(_amount - fromSp);
            uint256 feeCharged = chargeFee(_amount, withdrawFee, withdrawFeeDecimals);
            IERC20(depositToken).safeTransfer(vault, _amount - feeCharged);
            emit WithdrawStrat(_amount, feeCharged);
        }
    }

    function chargeFee(uint256 _amount, uint256 _fee, uint256 _decimals) public returns (uint256) {
        if (_fee > 0) {
            uint256 feeCharged = _amount * _fee / _decimals;
            IERC20(depositToken).safeTransfer(manager, feeCharged);
            return feeCharged;
        }
        return 0;
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
        emit Harvest(baseToken,baseBalance);
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
        emit PostionClosed(amount, balYield);
    }

    function rebalance() external {
        onlyManager();
        _closePostion();
        _deposit();
    }

    function _provideToSP() internal {
        uint256 _amount = IERC20(depositToken).balanceOf(address(this));
        uint256 inSp = (allocation * _amount) / PERCENTAGE_BASE;
        IStabilityPool(stabilityPool).provideToSP(inSp, collateralAssets);
    }

    function withdrawFromSP(uint256 _amount) internal {
        IStabilityPool(stabilityPool).withdrawFromSP(_amount, collateralAssets);
    }

    function addPool(address _collateralAsset, address _baseToken, address _pool) external returns (bool) {
        onlyManager();
        swapPools[_collateralAsset][_baseToken] = _pool;
        swapPools[_baseToken][_collateralAsset] = _pool;
        emit PoolAdded(_collateralAsset, _baseToken, _pool);
        return true;
    }

    function addOracle(address _asset, address _oracle, uint256 _timeout) external {
        onlyManager();
        oracles[_asset] = _oracle;
        oracleTimeout[_oracle] = _timeout;
        emit OracleAdded(_asset, _oracle);
    }

    function liquidate(address _asset, uint256 _n) public {
        TroveManagerOperations(troveManager).liquidateTroves(_asset, _n);
    }

    function onYield() internal {
        uint256 amount = IERC20(depositToken).balanceOf(address(this));
        uint256 mrktID = IDolomiteMargin(doloM).getMarketIdByTokenAddress(depositToken);
        IDepositWithdrawalRouter(doloRouter).depositWei(0, 0, mrktID, amount, IDepositWithdrawalRouter.EventFlag.None);
    }

    function offYield(uint256 _amount) internal {
        uint256 mrktID = IDolomiteMargin(doloM).getMarketIdByTokenAddress(depositToken);

        IDepositWithdrawalRouter(doloRouter).withdrawWei(0, 0, mrktID, _amount, AccountBalanceLib.BalanceCheckFlag.None);
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
        emit Harvest(baseToken,baseBal);
    }

    function setAllo(uint256 _newAllo) external returns (uint256) {
        onlyManager();
        if (_newAllo > PERCENTAGE_BASE) revert ExceedsMax(_newAllo, PERCENTAGE_BASE);
        allocation = _newAllo;
        emit newAllo(_newAllo);
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
        uint256 heartbeat = oracleTimeout[oracle];
        (, int256 answer,, uint256 updatedAt,) = ChainlinkAggregatorV3Interface(oracle).latestRoundData();
        uint256 oracleDecimals = ChainlinkAggregatorV3Interface(oracle).decimals();
        if (answer <= 0) revert FeedPriceNotPositive(answer);
        if (block.timestamp - updatedAt > heartbeat) {
            revert FeedHeartbeatExceeded(block.timestamp, updatedAt, heartbeat);
        }

        uint256 tokenDecimals = IERC20Metadata(_asset).decimals();

        // Normalize `_amount` to 18 decimals
        uint256 normalizedAmount = (_amount * 1e18) / (10 ** tokenDecimals);

        // Normalize price to 18 decimals too
        uint256 price = uint256(answer) * 1e18 / (10 ** oracleDecimals);
        return (normalizedAmount * price) / 1e18;
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
        uint256 heartbeat = oracleTimeout[oracle];
        (, int256 answer,, uint256 updatedAt,) = ChainlinkAggregatorV3Interface(oracle).latestRoundData();
        uint256 decimals = ChainlinkAggregatorV3Interface(oracle).decimals();
        if (answer <= 0) revert FeedPriceNotPositive(answer);
        if (block.timestamp - updatedAt > heartbeat) {
            revert FeedHeartbeatExceeded(block.timestamp, updatedAt, heartbeat);
        }
        return (uint256(answer), decimals);
    }

    function inCaseTokensGetStuck(address _token, address _receiver) public {
        onlyManager();
        if (_token == depositToken || _token == baseToken) revert SystemToken();
        if (_token == address(0)) revert ZeroAddress();
        uint256 balance = IERC20(_token).balanceOf(address(this));
        if (balance == 0) revert ZeroBalance();
        IERC20(_token).safeTransfer(_receiver, balance);
        emit SentFunds(_token, _receiver, balance);
    }

    function retireStrat() external {
        onlyVault();
        _closePostion();
        uint256 balance = IERC20(depositToken).balanceOf(address(this));
        IERC20(depositToken).safeTransfer(vault, balance);
        _pause();
    }

    function pause() public {
        onlyManager();
        _pause();
        _removeAllowances();
    }

    function unpause() public {
        onlyManager();
        _unpause();
        _giveAllowances();
    }

    function _giveAllowances() internal virtual {
        IERC20(depositToken).safeApprove(stabilityPool, type(uint256).max);
        IERC20(depositToken).safeApprove(router, type(uint256).max);
        IERC20(depositToken).safeApprove(doloRouter, type(uint256).max);
        if (depositToken != baseToken) {
            IERC20(baseToken).safeApprove(doloRouter, type(uint256).max);
            IERC20(baseToken).safeApprove(router, type(uint256).max);
        }

        for (uint256 i = 0; i < collateralAssets.length; i++) {
            IERC20(collateralAssets[i]).safeApprove(stabilityPool, type(uint256).max);
            IERC20(collateralAssets[i]).safeApprove(router, type(uint256).max);
            IERC20(collateralAssets[i]).safeApprove(doloRouter, type(uint256).max);
        }
    }

    function _giveAllowances(address _asset) internal virtual {
        IERC20(_asset).safeApprove(stabilityPool, type(uint256).max);
        IERC20(_asset).safeApprove(router, type(uint256).max);
        IERC20(_asset).safeApprove(doloRouter, type(uint256).max);
    }

    function _removeAllowances() internal virtual {
        IERC20(depositToken).safeApprove(stabilityPool, 0);
        IERC20(depositToken).safeApprove(router, 0);
        IERC20(depositToken).safeApprove(doloRouter, 0);
        if (depositToken != baseToken) {
            IERC20(baseToken).safeApprove(router, 0);
            IERC20(baseToken).safeApprove(doloRouter, 0);
        }

        for (uint256 i = 0; i < collateralAssets.length; i++) {
            IERC20(collateralAssets[i]).safeApprove(stabilityPool, 0);
            IERC20(collateralAssets[i]).safeApprove(router, 0);
            IERC20(collateralAssets[i]).safeApprove(doloRouter, 0);
        }
    }


    function _authorizeUpgrade(address) internal override onlyOwner {}
}
