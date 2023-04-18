// // SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.8;

import "src/oracles/WithdrawOracle.sol";
import "src/LiquidStaking.sol";
import "src/tokens/NETH.sol";
import "src/tokens/VNFT.sol";
import "src/registries/NodeOperatorRegistry.sol";
import "src/vault/ELVault.sol";
import "forge-std/Script.sol";
import "./utils/DeployProxy.sol";
import "src/vault/ConsensusVault.sol";
import "src/vault/ELVaultFactory.sol";
import "src/vault/NodeDaoTreasury.sol";

// Goerli settings
abstract contract GoerliHelperContractV2 {
    address deployerAddress = 0x7A7df7396A82A5F4eEb7e023C4874c00e8616157;
    DeployProxy deployer = DeployProxy(deployerAddress);

    address _daoMultisigContract = 0x6aE2F56C057e31a18224DBc6Ae32B0a5FBeDFCB0;

    address timelock = 0x558dfCfE91E2fF9BA83DA6190f7cCC8bc66c2cCb;

    address payable liquidStakingProxy = payable(0x949AC43bb71F8710B0F1193880b338f0323DeB1a);
    address payable operatorRegistryProxy = payable(0x20C43025E44984375c4dC882bFF2016C6E601f0A);
    address payable vnftProxy = payable(0x3CB42bb75Cf1BcC077010ac1E3d3Be22D13326FA);
    address payable neth = payable(0x408F53a38db844B167B66f001fDc49613E25eC78);
    address payable consensusVaultProxy = payable(0x138d5D3C2d7d68bFC653726c8a5E8bA301452202);


    // ==================== Oracle ====================

    // goerli: 1616508000
    // mainnet: 1606824023
    uint64 _genesisTime = 1616508000;
    // oracle member
    address[] memberArray = [
        0xe583DC38863aB4b5A94da77A6628e2119eaD4B18,
        0x3357c09eCf74C281B6f9CCfAf4D894979349AC4B,
        0x143848A303d424FD75995e5827358ba6d30a1801
    ];
}

// Mainnet settings
abstract contract MainnetHelperContractV2 {
    // https://etherscan.io/address/0x178b7401c32a4aab5ef128458888779eaaf4e78a
    address deployerAddress = 0x178B7401C32A4aab5EF128458888779eaAF4E78a;
    DeployProxy deployer = DeployProxy(deployerAddress);

    address _daoMultisigContract = 0x718b7885FEC8511DC8F2A378D3045c90e82d6A1d;

    address timelock = 0x16F692525f3b8c8a96F8c945D365Da958Fb5735B;

    address payable liquidStakingProxy = payable(0x8103151E2377e78C04a3d2564e20542680ed3096);
    address payable operatorRegistryProxy = payable(0x8742178Ac172eC7235E54808d5F327C30A51c492);
    address payable vnftProxy = payable(0x58553F5c5a6AEE89EaBFd42c231A18aB0872700d);
    address payable neth = payable(0xC6572019548dfeBA782bA5a2093C836626C7789A);
    address payable consensusVaultProxy = payable(0x4b8Dc35b44296D8D6DCc7aFEBBbe283c997E80Ae);

    // ==================== Oracle ====================

    // goerli: 1616508000
    // mainnet: 1606824023
    uint64 _genesisTime = 1606824023;
    // oracle member
    address[] memberArray = [
        0x080C185D164446746068Db1650850F453ffdB92c,
        0xad7457910Ba258904cFe9B676a68201455CE6e61,
        0xf4A30Ec717b7F3aCC7fAeD373C941086a292BD5E,
        0x22E0cAF2B2dD1E11602D58eEfE9865f80aA949c6
    ];
}

contract GoerliDeployNodeDaoTreasury is Script, GoerliHelperContractV2 {
    NodeDaoTreasury nodeDaoTreasury;
    address payable nodeDaoTreasuryProxy;

    function setUp() public {}

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        nodeDaoTreasury = new NodeDaoTreasury();
        console.log("===============nodeDaoTreasury=================", address(nodeDaoTreasury));

        nodeDaoTreasuryProxy = payable(deployer.deploy(address(nodeDaoTreasury)));
        console.log("===============nodeDaoTreasuryProxy=================", address(nodeDaoTreasuryProxy));

        NodeDaoTreasury(nodeDaoTreasuryProxy).initialize(_daoMultisigContract);
        NodeDaoTreasury(nodeDaoTreasuryProxy).transferOwnership(address(timelock));

        vm.stopBroadcast();
    }
}

contract MainnetDeployNodeDaoTreasury is Script, MainnetHelperContractV2 {
    NodeDaoTreasury nodeDaoTreasury;
    address payable nodeDaoTreasuryProxy;

    function setUp() public {}

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        nodeDaoTreasury = new NodeDaoTreasury();
        console.log("===============nodeDaoTreasury=================", address(nodeDaoTreasury));

        nodeDaoTreasuryProxy = payable(deployer.deploy(address(nodeDaoTreasury)));
        console.log("===============nodeDaoTreasuryProxy=================", address(nodeDaoTreasuryProxy));

        NodeDaoTreasury(nodeDaoTreasuryProxy).initialize(_daoMultisigContract);
        NodeDaoTreasury(nodeDaoTreasuryProxy).transferOwnership(address(timelock));

        vm.stopBroadcast();
    }
}

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

