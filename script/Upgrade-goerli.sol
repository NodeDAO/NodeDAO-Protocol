// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.8;

import "src/tokens/NETH.sol";
import "src/tokens/VNFT.sol";
import "src/registries/NodeOperatorRegistry.sol";
import "src/vault/ELVault.sol";
import "src/vault/ConsensusVault.sol";
import "src/vault/ELVaultFactory.sol";
import "src/LiquidStaking.sol";
import "./utils/DeployProxy.sol";
import "forge-std/Script.sol";
import "forge-std/console.sol";
import "src/OperatorSlash.sol";
import "src/WithdrawalRequest.sol";
import "src/oracles/WithdrawOracle.sol";
import "src/vault/VaultManager.sol";
import "src/vault/NodeDaoTreasury.sol";

// goerli delete --with-gas-price 30000000000
// forge script script/Upgrade-goerli.sol:DeployUpgradeImplementScript --rpc-url $GOERLI_RPC_URL --broadcast --verify --with-gas-price 30000000000 --retries 10 --delay 30
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

// goerli delete --with-gas-price 30000000000
// forge script script/Upgrade-goerli.sol:DeployVaultFactorysScript --rpc-url $GOERLI_RPC_URL --broadcast --verify --with-gas-price 30000000000 --retries 10 --delay 30
contract DeployVaultFactorysScript is Script {
    address payable liquidStakingProxy = payable(0x949AC43bb71F8710B0F1193880b338f0323DeB1a);
    address payable operatorRegistryProxy = payable(0x20C43025E44984375c4dC882bFF2016C6E601f0A);
    address payable dao = payable(0x6aE2F56C057e31a18224DBc6Ae32B0a5FBeDFCB0);

    ELVault vaultContract;
    ELVaultFactory vaultFactoryContract;
    address vaultFactoryContractProxy;

    function setUp() public {}

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // deploy ELVault implement
        vaultContract = new ELVault();

        // deploy ELVaultFactory implement
        vaultFactoryContract = new ELVaultFactory();

        DeployProxy deployer = new DeployProxy();
        deployer.setType("uups");

        // deploy ELVaultFactory proxy
        vaultFactoryContractProxy = deployer.deploy(address(vaultFactoryContract));

        ELVaultFactory(vaultFactoryContractProxy).initialize(address(vaultContract), liquidStakingProxy, dao);
        ELVaultFactory(vaultFactoryContractProxy).setNodeOperatorRegistry(operatorRegistryProxy);
        console.log("===============vaultFactoryContractProxy=================", address(vaultFactoryContractProxy));

        vm.stopBroadcast();
    }
}

// goerli delete --with-gas-price 30000000000
// forge script script/Upgrade-goerli.sol:DeployNewContractScript --rpc-url $GOERLI_RPC_URL --broadcast --verify --with-gas-price 30000000000 --retries 10 --delay 30
contract DeployNewContractScript is Script {
    address payable liquidStakingProxy = payable(0x949AC43bb71F8710B0F1193880b338f0323DeB1a);
    address payable operatorRegistryProxy = payable(0x20C43025E44984375c4dC882bFF2016C6E601f0A);
    address payable dao = payable(0x6aE2F56C057e31a18224DBc6Ae32B0a5FBeDFCB0);
    address payable vnftProxy = payable(0x3CB42bb75Cf1BcC077010ac1E3d3Be22D13326FA);
    address payable neth = payable(0x408F53a38db844B167B66f001fDc49613E25eC78);

    OperatorSlash operatorSlash;
    WithdrawalRequest withdrawalRequest;
    VaultManager vaultManager;
    NodeDaoTreasury nodeDaoTreasury;
    address operatorSlashProxy;
    address withdrawalRequestProxy;
    address withdrawOracleProxy;
    address vaultManagerProxy;
    address nodeDaoTreasuryProxy;

    function setUp() public {}

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        DeployProxy deployer = new DeployProxy();
        deployer.setType("uups");

        nodeDaoTreasury = new NodeDaoTreasury();
        console.log("===============nodeDaoTreasury=================", address(nodeDaoTreasury));
        operatorSlash = new OperatorSlash();
        console.log("===============operatorSlash=================", address(operatorSlash));
        withdrawalRequest = new WithdrawalRequest();
        console.log("===============withdrawalRequest=================", address(withdrawalRequest));
        vaultManager = new VaultManager();
        console.log("===============vaultManager=================", address(vaultManager));

        nodeDaoTreasuryProxy = deployer.deploy(address(nodeDaoTreasury));
        console.log("===============nodeDaoTreasuryProxy=================", address(nodeDaoTreasuryProxy));

        operatorSlashProxy = deployer.deploy(address(operatorSlash));
        console.log("===============operatorSlashProxy=================", address(operatorSlashProxy));

        withdrawalRequestProxy = deployer.deploy(address(withdrawalRequest));
        console.log("===============withdrawalRequestProxy=================", address(withdrawalRequestProxy));

        vaultManagerProxy = deployer.deploy(address(vaultManager));
        console.log("===============vaultManagerProxy=================", address(vaultManagerProxy));

        OperatorSlash(operatorSlashProxy).initialize(
            dao, liquidStakingProxy, vnftProxy, operatorRegistryProxy, withdrawalRequestProxy, vaultManagerProxy, 7200
        );

        WithdrawalRequest(withdrawalRequestProxy).initialize(
            dao, liquidStakingProxy, vnftProxy, neth, operatorRegistryProxy, vaultManagerProxy
        );

        VaultManager(vaultManagerProxy).initialize(
            dao, liquidStakingProxy, vnftProxy, operatorRegistryProxy, withdrawOracleProxy, operatorSlashProxy
        );

        vm.stopBroadcast();
    }
}
