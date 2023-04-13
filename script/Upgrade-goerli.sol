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

        vm.stopBroadcast();
    }
}

// goerli delete --with-gas-price 30000000000
// forge script script/Upgrade-goerli.sol:DeployVaultFactorysScript --rpc-url $GOERLI_RPC_URL --broadcast --verify --with-gas-price 30000000000 --retries 10 --delay 30
contract DeployVaultFactorysScript is Script {
    address payable liquidStakingProxy = payable(0xa8256fD3A31648D49D0f3551e6e45Db6f5f91d53);
    address payable operatorRegistryProxy = payable(0xD9d87abAd8651e1E69799416AEc54fCCdd1dAAcE);
    address payable dao = payable(0xc214f4fBb7C9348eF98CC09c83d528E3be2b63A5);

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
    address payable liquidStakingProxy = payable(0xa8256fD3A31648D49D0f3551e6e45Db6f5f91d53);
    address payable operatorRegistryProxy = payable(0xD9d87abAd8651e1E69799416AEc54fCCdd1dAAcE);
    address payable dao = payable(0xc214f4fBb7C9348eF98CC09c83d528E3be2b63A5);
    address payable vnftProxy = payable(0xe3CE494D51Cb9806187b5Deca1B4B06c97e52EFc);
    address payable neth = payable(0x78ef0463ae6BbF05969ef38B4cF90Ca03537a86e);

    OperatorSlash operatorSlash;
    WithdrawalRequest withdrawalRequest;
    WithdrawOracle withdrawOracle;
    VaultManager vaultManager;
    address operatorSlashProxy;
    address withdrawalRequestProxy;
    address withdrawOracleProxy;
    address vaultManagerProxy;

    function setUp() public {}

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        DeployProxy deployer = new DeployProxy();
        deployer.setType("uups");

        operatorSlash = new OperatorSlash();
        console.log("===============operatorSlash=================", address(operatorSlash));
        withdrawalRequest = new WithdrawalRequest();
        console.log("===============withdrawalRequest=================", address(withdrawalRequest));
        withdrawOracle = new WithdrawOracle();
        console.log("===============withdrawOracle=================", address(withdrawOracle));
        vaultManager = new VaultManager();
        console.log("===============vaultManager=================", address(vaultManager));

        operatorSlashProxy = deployer.deploy(address(operatorSlash));
        console.log("===============operatorSlashProxy=================", address(operatorSlashProxy));

        withdrawalRequestProxy = deployer.deploy(address(withdrawalRequest));
        console.log("===============withdrawalRequestProxy=================", address(withdrawalRequestProxy));

        withdrawOracleProxy = deployer.deploy(address(withdrawOracle));
        console.log("===============withdrawOracleProxy=================", address(withdrawOracleProxy));

        vaultManagerProxy = deployer.deploy(address(vaultManager));
        console.log("===============vaultManagerProxy=================", address(vaultManagerProxy));

        OperatorSlash(operatorSlashProxy).initialize(
            dao, liquidStakingProxy, vnftProxy, operatorRegistryProxy, withdrawalRequestProxy, vaultManagerProxy, 7200
        );

        WithdrawalRequest(withdrawalRequestProxy).initialize(
            dao, liquidStakingProxy, vnftProxy, neth, operatorRegistryProxy, withdrawalRequestProxy, vaultManagerProxy
        );

        VaultManager(vaultManagerProxy).initialize(
            dao, liquidStakingProxy, vnftProxy, withdrawOracleProxy, withdrawOracleProxy, operatorSlashProxy
        );

        vm.stopBroadcast();
    }
}
