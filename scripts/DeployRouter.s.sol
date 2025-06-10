import "forge-std/Script.sol";
import "forge-std/console.sol";

import "../src/strategies/MockRouter.sol";





contract DeployRouter is Script {
    address public pusd = 0xe19cE0aCF70DBD7ff9Cb80715f84aB0Fd72B57AC;
    address public wbtc = 0x321f90864fb21cdcddD0D67FE5e4Cbc812eC9e64;

    //address public router =0x3b57978b411E909424E98A6a506823Ec93a0CD85;


    function run() external {
        uint256 deployerPrivateKey = 0xd68f5d8c457f5675592a7d486aeb7de973a76b12e02430e7dc01956b27af0370;
        address deployer = vm.addr(deployerPrivateKey);
        vm.startBroadcast(deployerPrivateKey);
        console.log("Deploying contracts with account:", deployer);

        MockRouter router = new MockRouter();
        console.log("Router deployed at:", address(router));

        IERC20(pusd).transfer(address(router), 1000e18);
        IERC20(wbtc).transfer(address(router), 1e17);

        vm.stopBroadcast();
    }
}

//forge script scripts/DeployRouter.s.sol:DeployRouter --rpc-url https://node.botanixlabs.dev --broadcast -vvv --legacy --slow