// // SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.8;

import "src/LiquidStaking.sol";
import "forge-std/Script.sol";
import "./utils/DeployProxy.sol";
import "forge-std/console.sol";
import "src/ssv/SSVCluster.sol";
import "src/ssv/SSVManager.sol";
import "src/StakingManager.sol";

// Goerli settings
abstract contract GoerliHelperContractSSVModule {
    address deployerAddress = 0x7A7df7396A82A5F4eEb7e023C4874c00e8616157;
    DeployProxy deployer = DeployProxy(deployerAddress);

    address _daoEOA = 0x6aE2F56C057e31a18224DBc6Ae32B0a5FBeDFCB0;
    address _daoMultisigContract = 0x6aE2F56C057e31a18224DBc6Ae32B0a5FBeDFCB0;

    address timelock = 0x558dfCfE91E2fF9BA83DA6190f7cCC8bc66c2cCb;

    address payable liquidStakingProxy = payable(0x949AC43bb71F8710B0F1193880b338f0323DeB1a);
    address payable operatorRegistryProxy = payable(0x20C43025E44984375c4dC882bFF2016C6E601f0A);

    address ssvNetwork = 0xC3CD9A0aE89Fff83b71b58b6512D43F8a41f363D;
    address ssvToken = 0x3a9f01091C446bdE031E39ea8354647AFef091E7;
    address vnftProxy = 0x3CB42bb75Cf1BcC077010ac1E3d3Be22D13326FA;
}

// Mainnet settings
abstract contract MainnetHelperContractSSVModule {
    // https://etherscan.io/address/0x178b7401c32a4aab5ef128458888779eaaf4e78a
    address deployerAddress = 0x178B7401C32A4aab5EF128458888779eaAF4E78a;
    DeployProxy deployer = DeployProxy(deployerAddress);

    address _daoEOA = 0xeF76D4e75154739F75F6068b3470c7968cC3Fcd1;
    address _daoMultisigContract = 0x718b7885FEC8511DC8F2A378D3045c90e82d6A1d;

    address timelock = 0x16F692525f3b8c8a96F8c945D365Da958Fb5735B;

    address payable liquidStakingProxy = payable(0x8103151E2377e78C04a3d2564e20542680ed3096);
    address payable operatorRegistryProxy = payable(0x8742178Ac172eC7235E54808d5F327C30A51c492);
    address ssvNetwork = 0xDD9BC35aE942eF0cFa76930954a156B3fF30a4E1;
    address ssvToken = 0x9D65fF81a3c488d585bBfb0Bfe3c7707c7917f54;
    address vnftProxy = 0x58553F5c5a6AEE89EaBFd42c231A18aB0872700d;
}

abstract contract BaseContract {
    // impl
    SSVCluster ssvCluster;
    LiquidStaking liquidStaking;

    // proxy
    StakingManager stakingManager;
    SSVManager ssvManager;

    address stakingManagerProxy;
    address ssvManagerProxy;

    function deployContracts(DeployProxy deployer) public {
        // ssvCluster = new SSVCluster();
        // console.log("===============ssvCluster=================", address(ssvCluster));

        // liquidStaking = new LiquidStaking();
        // console.log("===============liquidStaking=================", address(liquidStaking));

        // stakingManager = new StakingManager();
        // console.log("===============stakingManager=================", address(stakingManager));

        ssvManager = new SSVManager();
        console.log("===============ssvManager=================", address(ssvManager));

        // stakingManagerProxy = deployer.deploy(address(stakingManager));
        // console.log("===============stakingManagerProxy=================", address(stakingManagerProxy));

        // ssvManagerProxy = deployer.deploy(address(ssvManager));
        // console.log("===============ssvManagerProxy=================", address(ssvManagerProxy));
    }

    function initializeContract(
        address dao,
        address liquidStakingProxy,
        address operatorRegistryProxy,
        address ssvNetwork,
        address ssvToken,
        address vnftProxy
    ) public {
        SSVManager(ssvManagerProxy).initialize(
            address(ssvCluster),
            dao,
            ssvNetwork,
            ssvToken,
            operatorRegistryProxy,
            address(stakingManagerProxy),
            address(vnftProxy)
        );

        StakingManager(stakingManagerProxy).initialize(
            dao, operatorRegistryProxy, liquidStakingProxy, address(ssvManagerProxy)
        );
    }

    function transferDaoToMultisig(address _daoMultisigContract) public {
        // transfer dao contract

        // ssvManagerProxy
        SSVManager(ssvManagerProxy).setDaoAddress(_daoMultisigContract);

        // stakingManagerProxy
        StakingManager(stakingManagerProxy).setDaoAddress(_daoMultisigContract);
    }

    function transferOwnerToTimelock(address timelock) public {
        // transfer owner to timelock

        SSVManager(ssvManagerProxy).transferOwnership(timelock);

        StakingManager(stakingManagerProxy).transferOwnership(timelock);
    }
}

contract GoerliDeploySSVModuleContractScript is Script, GoerliHelperContractSSVModule, BaseContract {
    function setUp() public {}

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        deployContracts(deployer);
        // initializeContract(_daoMultisigContract, liquidStakingProxy, operatorRegistryProxy, ssvNetwork, ssvToken);

        vm.stopBroadcast();
    }
}

contract MainnetDeploySSVModuleContractScript is Script, MainnetHelperContractSSVModule, BaseContract {
    function setUp() public {}

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        deployContracts(deployer);
        initializeContract(
            _daoMultisigContract, liquidStakingProxy, operatorRegistryProxy, ssvNetwork, ssvToken, vnftProxy
        );
        transferDaoToMultisig(_daoMultisigContract);
        transferOwnerToTimelock(timelock);

        vm.stopBroadcast();
    }
}
