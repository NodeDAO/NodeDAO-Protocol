// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.8;

import "forge-std/Test.sol";
import "src/oracles/BeaconOracle.sol";
import "src/LiquidStaking.sol";
import "src/tokens/NETH.sol";
import "src/tokens/VNFT.sol";
import "src/registries/NodeOperatorRegistry.sol";
import "src/vault/ELVault.sol";
import "src/vault/ConsensusVault.sol";
import "src/vault/ELVaultFactory.sol";
import "src/TimelockController.sol";
import "forge-std/console.sol";

// forge test --match-path test/DeployTest.t.sol -vvv --rpc-url $GOERLI_RPC_URL
contract DeployedTest is Test {
    address payable liquidStakingProxy = payable(0xa8256fD3A31648D49D0f3551e6e45Db6f5f91d53);

    TimelockController timelock;

    LiquidStaking liquidStaking;

    NETH neth;
    ELVault vaultContract;

    ELVaultFactory vaultFactoryContract;

    VNFT vnft;
    address vnftProxy;

    NodeOperatorRegistry operatorRegistry;
    address operatorRegistryProxy;

    BeaconOracle beaconOracle;
    address beaconOracleProxy;

    ConsensusVault consensusVault;
    address payable consensusVaultProxy;

    function setUp() public {
        liquidStaking = LiquidStaking(liquidStakingProxy);
    }

    function testLiquidStaking() public {
        console.log("getNethOut:", liquidStaking.getNethOut(1 ether));
        assertEq(address(0x6aE2F56C057e31a18224DBc6Ae32B0a5FBeDFCB0), liquidStaking.dao());
    }
}
