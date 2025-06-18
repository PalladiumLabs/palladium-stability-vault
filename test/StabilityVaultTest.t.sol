pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import "../src/strategies/StabilityVault.sol";
import "./MockDolomiteRouter.sol";
import "./MockDolomiteMargin.sol";
import "../src/vaults/RiveraAutoCompoundingVaultV2Public.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "../src/strategies/common/interfaces/IStrategy.sol";

contract StabilityVaultTest is Test {
    StabilityVault public strat;
    RiveraAutoCompoundingVaultV2Public public vault;

    MockDolomiteMargin public dolom;
    MockDolomiteRouter public dolomRouter;

    address public pusd = 0xe19cE0aCF70DBD7ff9Cb80715f84aB0Fd72B57AC;
    address public wbtc = 0x321f90864fb21cdcddD0D67FE5e4Cbc812eC9e64;

    address public stabilityPool = 0x56984Cc217B0a72DE3f641AF387EdD21164BbE78;
    address public vManagerOps = 0xd4B76b6e5E56F1DAD86c96D275831dEfdB9473c1;

    address public priceFeed = 0x800755300090fFE065437fe12751910c96452aA4;

    address public wbtcOracle = 0x717431E3E7951196BCE7B5b0d0593Dad1b6D5e2d;
    address public usdtOracle = 0x0f90132F5A42739f881f6864f171D26938a3c232;

    address public router = 0x519F144700152B23a1ac5b47aef92575542AfA84;

    address public deployer = 0xfB0140ea62F41f643959B2A4153bf908f80EA4aD;
    address public deployer2 = 0xFaBcc4b22fFEa25D01AC23c5d225D7B27CB1B6B8;

    string public rpc = "https://node.botanixlabs.dev";
    uint256 forkId;

    function setUp() public {
        console.log("Running StabilityVaultTest...");
        forkId = vm.createFork(rpc);
        vm.selectFork(forkId);
        vm.startPrank(deployer);
        dolomRouter = new MockDolomiteRouter();
        dolomRouter.setMarket(0, pusd);
        dolom = new MockDolomiteMargin(address(dolomRouter));
        dolom.setMarketIdByTokenAddress(pusd, 0);

        console.log("dolomRouter: ", address(dolomRouter));
        console.log("dolom: ", address(dolom));
    }

    function test_DeployRiveraAutoCompoundingVault() public {
        uint256 approvalDelay = 2 days;

        vault = new RiveraAutoCompoundingVaultV2Public(pusd, "yPUSD", "yPUSD", approvalDelay, 100000000e18);

        uint256 tvlCap = vault.totalTvlCap();
        assert(tvlCap == 100000000e18);
        assert(vault.approvalDelay() == approvalDelay);
        assert(vault.totalSupply() == 0);
        assert(vault.asset() == pusd);
    }

    function test_DeployStabilityVault() public {
        uint256 approvalDelay = 2 days;
        vault = new RiveraAutoCompoundingVaultV2Public(pusd, "yPUSD", "yPUSD", approvalDelay, 100000000e18);

        CommonAddress memory _commondAddress = CommonAddress(
            address(vault), deployer, router, vManagerOps, address(dolom), address(dolomRouter), 100, 30, 1000, 10, 1000
        );

        VaultConfig memory _configs = VaultConfig(pusd, pusd, stabilityPool, priceFeed);

        StabilityVault stratImpl = new StabilityVault();
        console.log("StabilityVault implementation deployed at:", address(stratImpl));

        ERC1967Proxy Proxy = new ERC1967Proxy(
            address(stratImpl), abi.encodeWithSelector(stratImpl.init.selector, _configs, _commondAddress)
        );
    }

    function test_Deposit() public {
        deployProtocol();
        vm.startPrank(deployer);
        uint256 amount = IERC20(pusd).balanceOf(deployer) / 2;
        console.log("Depositing amount:", amount);
        IERC20(pusd).approve(address(vault), amount);
        vault.deposit(amount, deployer);
        uint256 shares = vault.balanceOf(deployer);
        console.log("Shares received:", shares);
        assert(shares > 0);
        vm.stopPrank();
    }

    function test_Withdraw() public {
        uint256 pusdBalance = IERC20(pusd).balanceOf(deployer);
        console.log("PUSD balance before deposit:", pusdBalance);
        test_Deposit();
        vm.startPrank(deployer);
        uint256 shares = vault.balanceOf(deployer);
        console.log("Withdrawing shares:", shares);
        vault.redeem(shares, deployer, deployer);
        uint256 pusdBalanceAfter = IERC20(pusd).balanceOf(deployer);
        console.log("PUSD balance after withdraw:", pusdBalanceAfter);
    }

    function test_checkManger() public {
        deployProtocol();
        vm.startPrank(deployer);
        address manager = strat.manager();
        assert(manager == deployer);
        console.log("Manager is:", manager);
        vm.stopPrank();
    }

    function test_addColl() public {
        deployProtocol();
        vm.startPrank(deployer);
        strat.addCollateralAsset(wbtc, wbtcOracle, 9000);
        address checkOracle = strat.oracles(wbtc);
        assert(checkOracle == wbtcOracle);
    }

    function test_addPool() public {
        deployProtocol();
        vm.startPrank(deployer);
        address randomPool = address(10);
        strat.addPool(wbtc, pusd, randomPool);
        address checkPool = strat.swapPools(wbtc, pusd);
        assert(checkPool == randomPool);
        address checkPool2 = strat.swapPools(pusd, wbtc);
        assert(checkPool2 == randomPool);
    }

    function test_depositNotVault() public {
        deployProtocol();
        vm.startPrank(deployer);
        vm.expectRevert("!vault");
        strat.deposit();
    }

    function test_validOwner() public {
        deployProtocol();
        assertEq(strat.owner(), deployer);
    }

    function test_rebalanceNotManger() public {
        deployProtocol();
        vm.startPrank(deployer2);
        vm.expectRevert("!manager");
        strat.rebalance();
    }

    function deployProtocol() internal {
        vm.startPrank(deployer);
        uint256 approvalDelay = 2 days;
        vault = new RiveraAutoCompoundingVaultV2Public(pusd, "yPUSD", "yPUSD", approvalDelay, 100000000e18);

        CommonAddress memory _commondAddress = CommonAddress(
            address(vault), deployer, router, vManagerOps, address(dolom), address(dolomRouter), 100, 30, 1000, 10, 1000
        );

        VaultConfig memory _configs = VaultConfig(pusd, pusd, stabilityPool, priceFeed);

        StabilityVault stratImpl = new StabilityVault();
        console.log("StabilityVault implementation deployed at:", address(stratImpl));

        ERC1967Proxy Proxy = new ERC1967Proxy(
            address(stratImpl), abi.encodeWithSelector(stratImpl.init.selector, _configs, _commondAddress)
        );

        strat = StabilityVault(address(Proxy));
        IERC20(pusd).approve(address(vault), 10000e18);
        vault.init(IStrategy(address(strat)), 10e18);
        console.log("owner is", strat.owner());
        vm.stopPrank();
    }
}
