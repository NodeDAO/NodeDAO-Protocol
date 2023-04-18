// // SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.8;

import "src/LiquidStaking.sol";
import "src/tokens/VNFT.sol";
import "src/registries/NodeOperatorRegistry.sol";
import "forge-std/Script.sol";
import "src/vault/ConsensusVault.sol";
import "src/vault/NodeDaoTreasury.sol";

contract DeployUpgradeImplementScript is Script {
    LiquidStaking liquidStaking;
    VNFT vnft;
    NodeOperatorRegistry operatorRegistry;
    ConsensusVault consensusVault;

    function setUp() public {}

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // deploy vNFT implement
        vnft = new VNFT();
        console.log("===============vnft impl=================", address(vnft));
        // deploy NodeOperatorRegistry implement
        operatorRegistry = new NodeOperatorRegistry();
        console.log("===============operatorRegistry impl=================", address(operatorRegistry));
        // deploy LiquidStakingimplement
        liquidStaking = new LiquidStaking();
        console.log("===============liquidStaking impl=================", address(liquidStaking));

        consensusVault = new ConsensusVault();
        console.log("===============consensusVault impl=================", address(consensusVault));

        vm.stopBroadcast();
    }
}

contract GoerliDeployNodeDaoTreasury is Script {
    NodeDaoTreasury nodeDaoTreasury;

    address _daoEOA = 0x6aE2F56C057e31a18224DBc6Ae32B0a5FBeDFCB0;
    address timelock = 0x558dfCfE91E2fF9BA83DA6190f7cCC8bc66c2cCb;

    function setUp() public {}

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        nodeDaoTreasury = new NodeDaoTreasury(_daoEOA);
        console.log("===============nodeDaoTreasury=================", address(nodeDaoTreasury));

        nodeDaoTreasury.transferOwnership(address(timelock));

        vm.stopBroadcast();
    }
}

contract MainnetDeployNodeDaoTreasury is Script {
    NodeDaoTreasury nodeDaoTreasury;
    address payable nodeDaoTreasuryProxy;
    address _daoMultisigContract = 0x718b7885FEC8511DC8F2A378D3045c90e82d6A1d;
    address timelock = 0x16F692525f3b8c8a96F8c945D365Da958Fb5735B;

    function setUp() public {}

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        nodeDaoTreasury = new NodeDaoTreasury(_daoMultisigContract);
        console.log("===============nodeDaoTreasury=================", address(nodeDaoTreasury));

        NodeDaoTreasury(nodeDaoTreasuryProxy).transferOwnership(address(timelock));

        vm.stopBroadcast();
    }
}
