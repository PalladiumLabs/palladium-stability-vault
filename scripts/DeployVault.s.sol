import "forge-std/Script.sol";
import "forge-std/console.sol";

import "../src/strategies/StabilityVault.sol";
import "../src/strategies/MockRouter.sol";
import "../src/vaults/RiveraAutoCompoundingVaultV2Public.sol";
import "../src/strategies/common/interfaces/IStrategy.sol";
import "../src/strategies/interfaces/IUniV3Factory.sol";






contract DeployVault is Script {
    address public pusd = 0xe19cE0aCF70DBD7ff9Cb80715f84aB0Fd72B57AC;
    address public wbtc = 0x321f90864fb21cdcddD0D67FE5e4Cbc812eC9e64;

    address public stabilityPool=0x56984Cc217B0a72DE3f641AF387EdD21164BbE78;
    address public vManagerOps=0xd4B76b6e5E56F1DAD86c96D275831dEfdB9473c1;

    address public priceFeed=0x800755300090fFE065437fe12751910c96452aA4;

    address public wbtcOracle = 0x717431E3E7951196BCE7B5b0d0593Dad1b6D5e2d;
    address public usdtOracle = 0x0f90132F5A42739f881f6864f171D26938a3c232;

    address public router=0x519F144700152B23a1ac5b47aef92575542AfA84;

   //address public router = 0xA5E0AE4e5103dc71cA290AA3654830442357A489;

    // address public vault = 0x959CD58f13a7Be468e409F30F00decA027a63E6b;
    // address public strat = 0xDb90649CfAC238746bF6252Fbb9561144f47A7e0;

    // address public factory = 0xc89e6aD4aD42Eeb82dfBA4c301CDaEDfd794A778;
    // address public pool = 0xbf481538b236E799759548490A4171674311173E;


    function run() external {
        uint256 deployerPrivateKey = 0x6a5a53e3f3a884c0a8b7203402781d477d119d31e8295e65c9523472fb9fac72;
        address deployer = vm.addr(deployerPrivateKey);
        vm.startBroadcast(deployerPrivateKey);
        console.log("Deploying contracts with account:", deployer);

        RiveraAutoCompoundingVaultV2Public vault = new RiveraAutoCompoundingVaultV2Public(pusd , "yPUSD", "yPUSD",1000e18,1000000e18);

       StabilityVault strat = new StabilityVault();

      CommonAddress memory _commondAddress =  CommonAddress (
        address(vault),
        deployer ,
        router,
        vManagerOps,
        30,
        1000,
        10,
        1000
      );


      VaultConfig memory _configs =  VaultConfig(
        pusd,
        pusd,
        stabilityPool,
        priceFeed
      );
         strat.init(_configs, _commondAddress);
        vault.init(IStrategy(address(strat)));
        console.log("Vault deployed at:", address(vault));
        console.log("Strategy deployed at:", address(strat));

        strat.addOracle(pusd, usdtOracle);


          StabilityVault(strat).addCollateralAsset(wbtc, wbtcOracle);

        IERC20(pusd).approve(address(vault), 1000e18);
        RiveraAutoCompoundingVaultV2(vault).deposit(10e18, deployer);
        console.log("Deposit 10 PUSD to vault");

        RiveraAutoCompoundingVaultV2Public(vault).totalAssets();
        console.log("Total assets in vault:", RiveraAutoCompoundingVaultV2Public(vault).totalAssets());


        uint256 pcon = StabilityVault(strat).tokenAToTokenBConversion(wbtc,pusd,1e18);
        console.log("PUSD to WBTC conversion:", pcon);

        // StabilityVault(strat).harvest();

  

     //StabilityVault(strat).liquidate(wbtc, 10);
//     address[] memory assets = new address[](1);
// assets[0] = wbtc;

    // uint256 deposit = IStabilityPool(stabilityPool).getCompoundedDebtTokenDeposits(strat);
    // console.log("Deposit in stability pool:", deposit);

    // console.log("Total assets after in vault:", RiveraAutoCompoundingVaultV2Public(vault).totalAssets());

    // RiveraAutoCompoundingVaultV2(vault).redeem(10e18 , deployer , deployer);

    //       deposit = IStabilityPool(stabilityPool).getCompoundedDebtTokenDeposits(strat);
    // console.log("Deposit in stability pool:", deposit);
    

        

        vm.stopBroadcast();
    }
}


//forge script scripts/DeployVault.s.sol:DeployVault --rpc-url https://node.botanixlabs.dev --broadcast -vvv --legacy --slow

// Vault deployed at: 0xc9D9E6005085a08fD93ef279d0D648Aa593af9d6
// Strategy deployed at: 0x962b31EBc0CBAc8439B4ccED32635bdd850FA6DC