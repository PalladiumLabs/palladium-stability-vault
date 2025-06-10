import "forge-std/Script.sol";
import "forge-std/console.sol";

import "../src/strategies/Interfaces/IDepositWithdrawalRouter.sol";
import "../src/strategies/Interfaces/IDolomiteMargin.sol";
import "@openzeppelin/token/ERC20/IERC20.sol";

contract DoloDeploy is Script {
    address public depositToken = 0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1;

    address public doloM = 0x6Bd780E7fDf01D77e4d475c821f1e7AE05409072;
    address public router = 0xf8b2c637A68cF6A17b1DF9F8992EeBeFf63d2dFf;

    address public daiWhale = 0x07aE8551Be970cB1cCa11Dd7a11F47Ae82e70E67; //arb

    function run() external {
        uint256 deployerPrivateKey = 0xd68f5d8c457f5675592a7d486aeb7de973a76b12e02430e7dc01956b27af0370;
        address deployer = vm.addr(deployerPrivateKey);

        vm.startPrank(daiWhale);

        IERC20(depositToken).approve(router, type(uint256).max);
        uint256 mktID = IDolomiteMargin(doloM).getMarketIdByTokenAddress(
            depositToken
        );
        Account.Info memory account = Account.Info({
            owner: daiWhale,
            number: 0
        });
        console.log("Market ID for deposit token:", mktID);
        IDepositWithdrawalRouter(router).depositWei(
            0,
            0,
            mktID,
            1000e18,
            IDepositWithdrawalRouter.EventFlag.None
        );
        Types.Wei memory myWei = IDolomiteMargin(doloM).getAccountWei(
            account,
            mktID
        );

        console.log("Balance after deposit:", myWei.value);
        Types.Par memory myPar = IDolomiteMargin(doloM).getAccountPar(
            account,
            mktID
        );
        console.log("Par after deposit:", myPar.value);
        // vm.warp(block.timestamp + 400 days);

        IDepositWithdrawalRouter(router).withdrawWei(
            0,
            0,
            mktID,
            myWei.value,
            AccountBalanceLib.BalanceCheckFlag.None
        );
        myWei = IDolomiteMargin(doloM).getAccountWei(account, mktID);
        console.log("Balance after deposit:", myWei.value);
        myPar = IDolomiteMargin(doloM).getAccountPar(account, mktID);
        console.log("Par after deposit:", myPar.value);
    }
}

//forge script scripts/Dolo.s.sol:DoloDeploy --rpc-url https://node.botanixlabs.dev -vvv --legacy --slow
//forge script scripts/Dolo.s.sol:DoloDeploy --rpc-url https://1rpc.io/arb -vvv --legacy --slow
