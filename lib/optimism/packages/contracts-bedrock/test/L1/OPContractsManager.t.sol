// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

// Testing
import { Test, stdStorage, StdStorage } from "forge-std/Test.sol";
import { VmSafe } from "forge-std/Vm.sol";
import { CommonTest } from "test/setup/CommonTest.sol";
import { DeployOPChain_TestBase } from "test/opcm/DeployOPChain.t.sol";
import { DelegateCaller } from "test/mocks/Callers.sol";

// Scripts
import { DeployOPChainInput } from "scripts/deploy/DeployOPChain.s.sol";
import { DeployUtils } from "scripts/libraries/DeployUtils.sol";
import { Deploy } from "scripts/deploy/Deploy.s.sol";

// Libraries
import { EIP1967Helper } from "test/mocks/EIP1967Helper.sol";
import { Blueprint } from "src/libraries/Blueprint.sol";
import { ForgeArtifacts } from "scripts/libraries/ForgeArtifacts.sol";
import { Bytes } from "src/libraries/Bytes.sol";

// Interfaces
import { IAnchorStateRegistry } from "interfaces/dispute/IAnchorStateRegistry.sol";
import { IL1ERC721Bridge } from "interfaces/L1/IL1ERC721Bridge.sol";
import { IL1StandardBridge } from "interfaces/L1/IL1StandardBridge.sol";
import { IOptimismMintableERC20Factory } from "interfaces/universal/IOptimismMintableERC20Factory.sol";
import { IL1CrossDomainMessenger } from "interfaces/L1/IL1CrossDomainMessenger.sol";
import { IMIPS } from "interfaces/cannon/IMIPS.sol";
import { IOptimismPortal2 } from "interfaces/L1/IOptimismPortal2.sol";
import { IProxy } from "interfaces/universal/IProxy.sol";
import { IProxyAdmin } from "interfaces/universal/IProxyAdmin.sol";
import { ISuperchainConfig } from "interfaces/L1/ISuperchainConfig.sol";
import { IProtocolVersions } from "interfaces/L1/IProtocolVersions.sol";
import { IPreimageOracle } from "interfaces/cannon/IPreimageOracle.sol";
import { IFaultDisputeGame } from "interfaces/dispute/IFaultDisputeGame.sol";
import { IPermissionedDisputeGame } from "interfaces/dispute/IPermissionedDisputeGame.sol";
import { IDelayedWETH } from "interfaces/dispute/IDelayedWETH.sol";
import { IDisputeGame } from "interfaces/dispute/IDisputeGame.sol";
import { IDisputeGameFactory } from "interfaces/dispute/IDisputeGameFactory.sol";
import { ISystemConfig } from "interfaces/L1/ISystemConfig.sol";
import {
    IOPContractsManager,
    IOPCMImplementationsWithoutLockbox,
    IOPContractsManagerGameTypeAdder,
    IOPContractsManagerDeployer,
    IOPContractsManagerUpgrader,
    IOPContractsManagerContractsContainer
} from "interfaces/L1/IOPContractsManager.sol";
import { ISemver } from "interfaces/universal/ISemver.sol";
import { IETHLockbox } from "interfaces/L1/IETHLockbox.sol";

// Contracts
import {
    OPContractsManager,
    OPContractsManagerGameTypeAdder,
    OPContractsManagerDeployer,
    OPContractsManagerUpgrader,
    OPContractsManagerContractsContainer
} from "src/L1/OPContractsManager.sol";
import { Blueprint } from "src/libraries/Blueprint.sol";
import { IBigStepper } from "interfaces/dispute/IBigStepper.sol";
import { GameType, Duration, Hash, Claim } from "src/dispute/lib/LibUDT.sol";
import { Proposal, GameTypes } from "src/dispute/lib/Types.sol";

// Exposes internal functions for testing.
contract OPContractsManager_Harness is OPContractsManager {
    constructor(
        OPContractsManagerGameTypeAdder _opcmGameTypeAdder,
        OPContractsManagerDeployer _opcmDeployer,
        OPContractsManagerUpgrader _opcmUpgrader,
        ISuperchainConfig _superchainConfig,
        IProtocolVersions _protocolVersions,
        IProxyAdmin _superchainProxyAdmin,
        string memory _l1ContractsRelease,
        address _upgradeController
    )
        OPContractsManager(
            _opcmGameTypeAdder,
            _opcmDeployer,
            _opcmUpgrader,
            _superchainConfig,
            _protocolVersions,
            _superchainProxyAdmin,
            _l1ContractsRelease,
            _upgradeController
        )
    { }

    function chainIdToBatchInboxAddress_exposed(uint256 l2ChainId) public view returns (address) {
        return super.chainIdToBatchInboxAddress(l2ChainId);
    }
}

// Unlike other test suites, we intentionally do not inherit from CommonTest or Setup. This is
// because OPContractsManager acts as a deploy script, so we start from a clean slate here and
// work OPContractsManager's deployment into the existing test setup, instead of using the existing
// test setup to deploy OPContractsManager. We do however inherit from DeployOPChain_TestBase so
// we can use its setup to deploy the implementations similarly to how a real deployment would
// happen.
contract OPContractsManager_Deploy_Test is DeployOPChain_TestBase {
    using stdStorage for StdStorage;

    event Deployed(uint256 indexed l2ChainId, address indexed deployer, bytes deployOutput);

    function setUp() public override {
        DeployOPChain_TestBase.setUp();

        doi.set(doi.opChainProxyAdminOwner.selector, opChainProxyAdminOwner);
        doi.set(doi.systemConfigOwner.selector, systemConfigOwner);
        doi.set(doi.batcher.selector, batcher);
        doi.set(doi.unsafeBlockSigner.selector, unsafeBlockSigner);
        doi.set(doi.proposer.selector, proposer);
        doi.set(doi.challenger.selector, challenger);
        doi.set(doi.basefeeScalar.selector, basefeeScalar);
        doi.set(doi.blobBaseFeeScalar.selector, blobBaseFeeScalar);
        doi.set(doi.l2ChainId.selector, l2ChainId);
        doi.set(doi.opcm.selector, address(opcm));
        doi.set(doi.gasLimit.selector, gasLimit);

        doi.set(doi.disputeGameType.selector, disputeGameType);
        doi.set(doi.disputeAbsolutePrestate.selector, disputeAbsolutePrestate);
        doi.set(doi.disputeMaxGameDepth.selector, disputeMaxGameDepth);
        doi.set(doi.disputeSplitDepth.selector, disputeSplitDepth);
        doi.set(doi.disputeClockExtension.selector, disputeClockExtension);
        doi.set(doi.disputeMaxClockDuration.selector, disputeMaxClockDuration);
    }

    // This helper function is used to convert the input struct type defined in DeployOPChain.s.sol
    // to the input struct type defined in OPContractsManager.sol.
    function toOPCMDeployInput(DeployOPChainInput _doi)
        internal
        view
        returns (IOPContractsManager.DeployInput memory)
    {
        return IOPContractsManager.DeployInput({
            roles: IOPContractsManager.Roles({
                opChainProxyAdminOwner: _doi.opChainProxyAdminOwner(),
                systemConfigOwner: _doi.systemConfigOwner(),
                batcher: _doi.batcher(),
                unsafeBlockSigner: _doi.unsafeBlockSigner(),
                proposer: _doi.proposer(),
                challenger: _doi.challenger()
            }),
            basefeeScalar: _doi.basefeeScalar(),
            blobBasefeeScalar: _doi.blobBaseFeeScalar(),
            l2ChainId: _doi.l2ChainId(),
            startingAnchorRoot: _doi.startingAnchorRoot(),
            saltMixer: _doi.saltMixer(),
            gasLimit: _doi.gasLimit(),
            disputeGameType: _doi.disputeGameType(),
            disputeAbsolutePrestate: _doi.disputeAbsolutePrestate(),
            disputeMaxGameDepth: _doi.disputeMaxGameDepth(),
            disputeSplitDepth: _doi.disputeSplitDepth(),
            disputeClockExtension: _doi.disputeClockExtension(),
            disputeMaxClockDuration: _doi.disputeMaxClockDuration()
        });
    }

    function test_deploy_l2ChainIdEqualsZero_reverts() public {
        IOPContractsManager.DeployInput memory deployInput = toOPCMDeployInput(doi);
        deployInput.l2ChainId = 0;
        vm.expectRevert(IOPContractsManager.InvalidChainId.selector);
        opcm.deploy(deployInput);
    }

    function test_deploy_l2ChainIdEqualsCurrentChainId_reverts() public {
        IOPContractsManager.DeployInput memory deployInput = toOPCMDeployInput(doi);
        deployInput.l2ChainId = block.chainid;

        vm.expectRevert(IOPContractsManager.InvalidChainId.selector);
        opcm.deploy(deployInput);
    }

    function test_deploy_succeeds() public {
        vm.expectEmit(true, true, true, false); // TODO precompute the expected `deployOutput`.
        emit Deployed(doi.l2ChainId(), address(this), bytes(""));
        opcm.deploy(toOPCMDeployInput(doi));
    }
}

// These tests use the harness which exposes internal functions for testing.
contract OPContractsManager_InternalMethods_Test is Test {
    OPContractsManager_Harness opcmHarness;

    function setUp() public {
        ISuperchainConfig superchainConfigProxy = ISuperchainConfig(makeAddr("superchainConfig"));
        IProtocolVersions protocolVersionsProxy = IProtocolVersions(makeAddr("protocolVersions"));
        IProxyAdmin superchainProxyAdmin = IProxyAdmin(makeAddr("superchainProxyAdmin"));
        address upgradeController = makeAddr("upgradeController");
        OPContractsManager.Blueprints memory emptyBlueprints;
        OPContractsManager.Implementations memory emptyImpls;
        vm.etch(address(superchainConfigProxy), hex"01");
        vm.etch(address(protocolVersionsProxy), hex"01");

        OPContractsManagerContractsContainer container =
            new OPContractsManagerContractsContainer(emptyBlueprints, emptyImpls);

        opcmHarness = new OPContractsManager_Harness({
            _opcmGameTypeAdder: new OPContractsManagerGameTypeAdder(container),
            _opcmDeployer: new OPContractsManagerDeployer(container),
            _opcmUpgrader: new OPContractsManagerUpgrader(container),
            _superchainConfig: superchainConfigProxy,
            _protocolVersions: protocolVersionsProxy,
            _superchainProxyAdmin: superchainProxyAdmin,
            _l1ContractsRelease: "dev",
            _upgradeController: upgradeController
        });
    }

    function test_calculatesBatchInboxAddress_succeeds() public view {
        // These test vectors were calculated manually:
        //   1. Compute the bytes32 encoding of the chainId: bytes32(uint256(chainId));
        //   2. Hash it and manually take the first 19 bytes, and prefixed it with 0x00.
        uint256 chainId = 1234;
        address expected = 0x0017FA14b0d73Aa6A26D6b8720c1c84b50984f5C;
        address actual = opcmHarness.chainIdToBatchInboxAddress_exposed(chainId);
        vm.assertEq(expected, actual);

        chainId = type(uint256).max;
        expected = 0x00a9C584056064687E149968cBaB758a3376D22A;
        actual = opcmHarness.chainIdToBatchInboxAddress_exposed(chainId);
        vm.assertEq(expected, actual);
    }
}

contract OPContractsManager_Upgrade_Harness is CommonTest {
    // The Upgraded event emitted by the Proxy contract.
    event Upgraded(address indexed implementation);

    // The Upgraded event emitted by the OPContractsManager contract.
    event Upgraded(uint256 indexed l2ChainId, ISystemConfig indexed systemConfig, address indexed upgrader);

    // The AddressSet event emitted by the AddressManager contract.
    event AddressSet(string indexed name, address newAddress, address oldAddress);

    // The AdminChanged event emitted by the Proxy contract at init time or when the admin is changed.
    event AdminChanged(address previousAdmin, address newAdmin);

    // The ImplementationSet event emitted by the DisputeGameFactory contract.
    event ImplementationSet(address indexed impl, GameType indexed gameType);

    uint256 l2ChainId;
    IProxyAdmin proxyAdmin;
    IProxyAdmin superchainProxyAdmin;
    address upgrader;
    IOPContractsManager.OpChainConfig[] opChainConfigs;
    Claim absolutePrestate;
    string public opChain = vm.envOr("FORK_OP_CHAIN", string("op"));

    function setUp() public virtual override {
        super.disableUpgradedFork();
        super.setUp();
        if (!isForkTest()) {
            // This test is only supported in forked tests, as we are testing the upgrade.
            vm.skip(true);
        }

        skipIfOpsRepoTest(
            "OPContractsManager_Upgrade_Harness: cannot test upgrade on superchain ops repo upgrade tests"
        );

        absolutePrestate = Claim.wrap(bytes32(keccak256("absolutePrestate")));
        proxyAdmin = IProxyAdmin(EIP1967Helper.getAdmin(address(systemConfig)));
        superchainProxyAdmin = IProxyAdmin(EIP1967Helper.getAdmin(address(superchainConfig)));
        upgrader = proxyAdmin.owner();
        vm.label(upgrader, "ProxyAdmin Owner");

        // Set the upgrader to be a DelegateCaller so we can test the upgrade
        vm.etch(upgrader, vm.getDeployedCode("test/mocks/Callers.sol:DelegateCaller"));

        opChainConfigs.push(
            IOPContractsManager.OpChainConfig({
                systemConfigProxy: systemConfig,
                proxyAdmin: proxyAdmin,
                absolutePrestate: absolutePrestate
            })
        );

        // Retrieve the l2ChainId, which was read from the superchain-registry, and saved in Artifacts
        // encoded as an address.
        l2ChainId = uint256(uint160(address(artifacts.mustGetAddress("L2ChainId"))));

        delayedWETHPermissionedGameProxy =
            IDelayedWETH(payable(artifacts.mustGetAddress("PermissionedDelayedWETHProxy")));
        delayedWeth = IDelayedWETH(payable(artifacts.mustGetAddress("PermissionlessDelayedWETHProxy")));
        permissionedDisputeGame = IPermissionedDisputeGame(address(artifacts.mustGetAddress("PermissionedDisputeGame")));
        faultDisputeGame = IFaultDisputeGame(address(artifacts.mustGetAddress("FaultDisputeGame")));
    }

    function expectEmitUpgraded(address impl, address proxy) public {
        vm.expectEmit(proxy);
        emit Upgraded(impl);
    }

    function runUpgrade13UpgradeAndChecks(address _delegateCaller) public {
        // The address below corresponds with the address of the v2.0.0-rc.1 OPCM on mainnet.
        address OPCM_ADDRESS = 0x026b2F158255Beac46c1E7c6b8BbF29A4b6A7B76;

        IOPContractsManager deployedOPCM = IOPContractsManager(OPCM_ADDRESS);
        IOPCMImplementationsWithoutLockbox.Implementations memory impls =
            IOPCMImplementationsWithoutLockbox(address(deployedOPCM)).implementations();

        address mainnetPAO = artifacts.mustGetAddress("SuperchainConfigProxy");

        // If the delegate caller is not the mainnet PAO, we need to call upgrade as the mainnet PAO first.
        if (_delegateCaller != mainnetPAO) {
            IOPContractsManager.OpChainConfig[] memory opmChain = new IOPContractsManager.OpChainConfig[](0);
            ISuperchainConfig superchainConfig = ISuperchainConfig(mainnetPAO);

            address opmUpgrader = IProxyAdmin(EIP1967Helper.getAdmin(address(superchainConfig))).owner();
            vm.etch(opmUpgrader, vm.getDeployedCode("test/mocks/Callers.sol:DelegateCaller"));

            DelegateCaller(opmUpgrader).dcForward(OPCM_ADDRESS, abi.encodeCall(IOPContractsManager.upgrade, (opmChain)));
        }

        // Cache the old L1xDM address so we can look for it in the AddressManager's event
        address oldL1CrossDomainMessenger = addressManager.getAddress("OVM_L1CrossDomainMessenger");

        // Predict the address of the new AnchorStateRegistry proxy
        bytes32 salt = keccak256(
            abi.encode(
                l2ChainId,
                string.concat(
                    string(bytes.concat(bytes32(uint256(uint160(address(opChainConfigs[0].systemConfigProxy))))))
                ),
                "AnchorStateRegistry"
            )
        );
        address proxyBp = deployedOPCM.blueprints().proxy;
        Blueprint.Preamble memory preamble = Blueprint.parseBlueprintPreamble(proxyBp.code);
        bytes memory initCode = bytes.concat(preamble.initcode, abi.encode(proxyAdmin));
        address newAnchorStateRegistryProxy = vm.computeCreate2Address(salt, keccak256(initCode), _delegateCaller);
        vm.label(newAnchorStateRegistryProxy, "NewAnchorStateRegistryProxy");

        expectEmitUpgraded(impls.systemConfigImpl, address(systemConfig));
        vm.expectEmit(address(addressManager));
        emit AddressSet("OVM_L1CrossDomainMessenger", impls.l1CrossDomainMessengerImpl, oldL1CrossDomainMessenger);
        // This is where we would emit an event for the L1StandardBridge however
        // the Chugsplash proxy does not emit such an event.
        expectEmitUpgraded(impls.l1ERC721BridgeImpl, address(l1ERC721Bridge));
        expectEmitUpgraded(impls.disputeGameFactoryImpl, address(disputeGameFactory));
        expectEmitUpgraded(impls.optimismPortalImpl, address(optimismPortal2));
        expectEmitUpgraded(impls.optimismMintableERC20FactoryImpl, address(l1OptimismMintableERC20Factory));
        vm.expectEmit(address(newAnchorStateRegistryProxy));
        emit AdminChanged(address(0), address(proxyAdmin));
        expectEmitUpgraded(impls.anchorStateRegistryImpl, address(newAnchorStateRegistryProxy));
        expectEmitUpgraded(impls.delayedWETHImpl, address(delayedWETHPermissionedGameProxy));

        // We don't yet know the address of the new permissionedGame which will be deployed by the
        // OPContractsManager.upgrade() call, so ignore the first topic.
        vm.expectEmit(false, true, true, true, address(disputeGameFactory));
        emit ImplementationSet(address(0), GameTypes.PERMISSIONED_CANNON);

        IFaultDisputeGame oldFDG = IFaultDisputeGame(address(disputeGameFactory.gameImpls(GameTypes.CANNON)));
        if (address(oldFDG) != address(0)) {
            IDelayedWETH weth = oldFDG.weth();
            expectEmitUpgraded(impls.delayedWETHImpl, address(weth));

            // Ignore the first topic for the same reason as the previous comment.
            vm.expectEmit(false, true, true, true, address(disputeGameFactory));
            emit ImplementationSet(address(0), GameTypes.CANNON);
        }

        vm.expectEmit(address(_delegateCaller));
        emit Upgraded(l2ChainId, opChainConfigs[0].systemConfigProxy, address(_delegateCaller));

        // Temporarily replace the upgrader with a DelegateCaller so we can test the upgrade,
        // then reset its code to the original code.
        bytes memory delegateCallerCode = address(_delegateCaller).code;
        vm.etch(_delegateCaller, vm.getDeployedCode("test/mocks/Callers.sol:DelegateCaller"));

        DelegateCaller(_delegateCaller).dcForward(
            address(deployedOPCM), abi.encodeCall(IOPContractsManager.upgrade, (opChainConfigs))
        );

        VmSafe.Gas memory gas = vm.lastCallGas();

        // Less than 90% of the gas target of 20M to account for the gas used by using Safe.
        assertLt(gas.gasTotalUsed, 0.9 * 20_000_000, "Upgrade exceeds gas target of 15M");

        vm.etch(_delegateCaller, delegateCallerCode);

        // Check the implementations of the core addresses
        assertEq(impls.systemConfigImpl, EIP1967Helper.getImplementation(address(systemConfig)));
        assertEq(impls.l1ERC721BridgeImpl, EIP1967Helper.getImplementation(address(l1ERC721Bridge)));
        assertEq(impls.disputeGameFactoryImpl, EIP1967Helper.getImplementation(address(disputeGameFactory)));
        assertEq(impls.optimismPortalImpl, EIP1967Helper.getImplementation(address(optimismPortal2)));
        assertEq(
            impls.optimismMintableERC20FactoryImpl,
            EIP1967Helper.getImplementation(address(l1OptimismMintableERC20Factory))
        );
        assertEq(impls.l1StandardBridgeImpl, EIP1967Helper.getImplementation(address(l1StandardBridge)));
        assertEq(impls.l1CrossDomainMessengerImpl, addressManager.getAddress("OVM_L1CrossDomainMessenger"));

        // Check the implementations of the FP contracts
        assertEq(impls.anchorStateRegistryImpl, EIP1967Helper.getImplementation(address(newAnchorStateRegistryProxy)));
        assertEq(impls.delayedWETHImpl, EIP1967Helper.getImplementation(address(delayedWETHPermissionedGameProxy)));

        // Check that the PermissionedDisputeGame is upgraded to the expected version, references
        // the correct anchor state and has the mipsImpl.
        IPermissionedDisputeGame pdg =
            IPermissionedDisputeGame(address(disputeGameFactory.gameImpls(GameTypes.PERMISSIONED_CANNON)));
        assertEq(ISemver(address(pdg)).version(), "1.4.1");
        assertEq(address(pdg.anchorStateRegistry()), address(newAnchorStateRegistryProxy));
        assertEq(address(pdg.vm()), impls.mipsImpl);

        if (address(oldFDG) != address(0)) {
            // Check that the PermissionlessDisputeGame is upgraded to the expected version
            IFaultDisputeGame newFDG = IFaultDisputeGame(address(disputeGameFactory.gameImpls(GameTypes.CANNON)));
            // Check that the PermissionlessDisputeGame is upgraded to the expected version, references
            // the correct anchor state and has the mipsImpl.
            assertEq(impls.delayedWETHImpl, EIP1967Helper.getImplementation(address(newFDG.weth())));
            assertEq(ISemver(address(newFDG)).version(), "1.4.1");
            assertEq(address(newFDG.anchorStateRegistry()), address(newAnchorStateRegistryProxy));
            assertEq(address(newFDG.vm()), impls.mipsImpl);
        }
    }

    function runUpgrade14UpgradeAndChecks(address _delegateCaller) public {
        address OPCM_ADDRESS = 0x3A1f523a4bc09cd344A2745a108Bb0398288094F;

        IOPContractsManager deployedOPCM = IOPContractsManager(OPCM_ADDRESS);
        IOPCMImplementationsWithoutLockbox.Implementations memory impls =
            IOPCMImplementationsWithoutLockbox(address(deployedOPCM)).implementations();

        address mainnetPAO = artifacts.mustGetAddress("SuperchainConfigProxy");

        // If the delegate caller is not the mainnet PAO, we need to call upgrade as the mainnet PAO first.
        if (_delegateCaller != mainnetPAO) {
            IOPContractsManager.OpChainConfig[] memory opmChain = new IOPContractsManager.OpChainConfig[](0);
            ISuperchainConfig superchainConfig = ISuperchainConfig(mainnetPAO);

            address opmUpgrader = IProxyAdmin(EIP1967Helper.getAdmin(address(superchainConfig))).owner();
            vm.etch(opmUpgrader, vm.getDeployedCode("test/mocks/Callers.sol:DelegateCaller"));

            DelegateCaller(opmUpgrader).dcForward(OPCM_ADDRESS, abi.encodeCall(IOPContractsManager.upgrade, (opmChain)));
        }

        // sanity check
        IPermissionedDisputeGame oldPDG =
            IPermissionedDisputeGame(address(disputeGameFactory.gameImpls(GameTypes.PERMISSIONED_CANNON)));
        IFaultDisputeGame oldFDG = IFaultDisputeGame(address(disputeGameFactory.gameImpls(GameTypes.CANNON)));

        // Sanity check that the mips IMPL is not MIPS64
        assertNotEq(address(oldPDG.vm()), impls.mipsImpl);

        // We don't yet know the address of the new permissionedGame which will be deployed by the
        // OPContractsManager.upgrade() call, so ignore the first topic.
        vm.expectEmit(false, true, true, true, address(disputeGameFactory));
        emit ImplementationSet(address(0), GameTypes.PERMISSIONED_CANNON);

        if (address(oldFDG) != address(0)) {
            // Sanity check that the mips IMPL is not MIPS64
            assertNotEq(address(oldFDG.vm()), impls.mipsImpl);
            // Ignore the first topic for the same reason as the previous comment.
            vm.expectEmit(false, true, true, true, address(disputeGameFactory));
            emit ImplementationSet(address(0), GameTypes.CANNON);
        }
        vm.expectEmit(address(_delegateCaller));
        emit Upgraded(l2ChainId, opChainConfigs[0].systemConfigProxy, address(_delegateCaller));

        // Temporarily replace the upgrader with a DelegateCaller so we can test the upgrade,
        // then reset its code to the original code.
        bytes memory delegateCallerCode = address(_delegateCaller).code;
        vm.etch(_delegateCaller, vm.getDeployedCode("test/mocks/Callers.sol:DelegateCaller"));

        DelegateCaller(_delegateCaller).dcForward(
            address(deployedOPCM), abi.encodeCall(IOPContractsManager.upgrade, (opChainConfigs))
        );

        VmSafe.Gas memory gas = vm.lastCallGas();

        // Less than 90% of the gas target of 20M to account for the gas used by using Safe.
        assertLt(gas.gasTotalUsed, 0.9 * 20_000_000, "Upgrade exceeds gas target of 15M");

        vm.etch(_delegateCaller, delegateCallerCode);

        // Check that the PermissionedDisputeGame is upgraded to the expected version, references
        // the correct anchor state and has the mipsImpl.
        IPermissionedDisputeGame pdg =
            IPermissionedDisputeGame(address(disputeGameFactory.gameImpls(GameTypes.PERMISSIONED_CANNON)));
        assertEq(ISemver(address(pdg)).version(), "1.4.1");
        assertEq(address(pdg.vm()), impls.mipsImpl);

        // Check that the SystemConfig is upgraded to the expected version
        assertEq(ISemver(address(systemConfig)).version(), "2.5.0");
        assertEq(impls.systemConfigImpl, EIP1967Helper.getImplementation(address(systemConfig)));

        if (address(oldFDG) != address(0)) {
            // Check that the PermissionlessDisputeGame is upgraded to the expected version
            IFaultDisputeGame newFDG = IFaultDisputeGame(address(disputeGameFactory.gameImpls(GameTypes.CANNON)));
            // Check that the PermissionlessDisputeGame is upgraded to the expected version, references
            // the correct anchor state and has the mipsImpl.
            assertEq(ISemver(address(newFDG)).version(), "1.4.1");
            assertEq(address(newFDG.vm()), impls.mipsImpl);
        }
    }

    function runUpgrade15UpgradeAndChecks(address _delegateCaller) public {
        IOPContractsManager.Implementations memory impls = opcm.implementations();

        // Predict the address of the new AnchorStateRegistry proxy.
        // Subcontext to avoid stack too deep.
        address newAsrProxy;
        {
            // Compute the salt using the system config address.
            bytes32 salt = keccak256(
                abi.encode(
                    l2ChainId,
                    string.concat(string(bytes.concat(bytes32(uint256(uint160(address(systemConfig))))))),
                    "AnchorStateRegistry-SOT"
                )
            );

            // Use the actual proxy instead of the local code so we can reuse this test.
            address proxyBp = opcm.blueprints().proxy;
            Blueprint.Preamble memory preamble = Blueprint.parseBlueprintPreamble(proxyBp.code);
            bytes memory initCode = bytes.concat(preamble.initcode, abi.encode(proxyAdmin));
            newAsrProxy = vm.computeCreate2Address(salt, keccak256(initCode), _delegateCaller);
            vm.label(newAsrProxy, "NewAnchorStateRegistryProxy");
        }

        // Grab the PermissionedDisputeGame and FaultDisputeGame implementations before upgrade.
        address oldPDGImpl = address(disputeGameFactory.gameImpls(GameTypes.PERMISSIONED_CANNON));
        address oldFDGImpl = address(disputeGameFactory.gameImpls(GameTypes.CANNON));
        IPermissionedDisputeGame oldPDG = IPermissionedDisputeGame(oldPDGImpl);
        IFaultDisputeGame oldFDG = IFaultDisputeGame(oldFDGImpl);

        // Expect the SystemConfig and OptimismPortal to be upgraded.
        expectEmitUpgraded(impls.systemConfigImpl, address(systemConfig));
        expectEmitUpgraded(impls.optimismPortalImpl, address(optimismPortal2));

        // We always expect the PermissionedDisputeGame to be deployed. We don't yet know the
        // address of the new permissionedGame which will be deployed by the
        // OPContractsManager.upgrade() call, so ignore the first topic.
        vm.expectEmit(false, true, true, true, address(disputeGameFactory));
        emit ImplementationSet(address(0), GameTypes.PERMISSIONED_CANNON);

        // If the old FaultDisputeGame exists, we expect it to be upgraded.
        if (address(oldFDG) != address(0)) {
            // Ignore the first topic for the same reason as the previous comment.
            vm.expectEmit(false, true, true, true, address(disputeGameFactory));
            emit ImplementationSet(address(0), GameTypes.CANNON);
        }

        vm.expectEmit(address(_delegateCaller));
        emit Upgraded(l2ChainId, systemConfig, address(_delegateCaller));

        // Temporarily replace the upgrader with a DelegateCaller so we can test the upgrade,
        // then reset its code to the original code.
        bytes memory delegateCallerCode = address(_delegateCaller).code;
        vm.etch(_delegateCaller, vm.getDeployedCode("test/mocks/Callers.sol:DelegateCaller"));

        // Execute the upgrade.
        // We use the new format here, not the legacy one.
        DelegateCaller(_delegateCaller).dcForward(
            address(opcm), abi.encodeCall(IOPContractsManager.upgrade, (opChainConfigs))
        );

        // Less than 90% of the gas target of 20M to account for the gas used by using Safe.
        VmSafe.Gas memory gas = vm.lastCallGas();
        assertLt(gas.gasTotalUsed, 0.9 * 20_000_000, "Upgrade exceeds gas target of 15M");

        // Reset the upgrader's code to the original code.
        vm.etch(_delegateCaller, delegateCallerCode);

        // Grab the new implementations.
        address newPDGImpl = address(disputeGameFactory.gameImpls(GameTypes.PERMISSIONED_CANNON));
        IPermissionedDisputeGame pdg = IPermissionedDisputeGame(newPDGImpl);
        address newFDGImpl = address(disputeGameFactory.gameImpls(GameTypes.CANNON));
        IFaultDisputeGame fdg = IFaultDisputeGame(newFDGImpl);

        // Check that the PermissionedDisputeGame is upgraded to the expected version, references
        // the correct anchor state and has the mipsImpl. Although Upgrade 15 doesn't actually
        // change any of this, we might as well check it again.
        assertEq(ISemver(address(pdg)).version(), "1.5.0");
        assertEq(address(pdg.vm()), impls.mipsImpl);
        assertEq(pdg.l2ChainId(), oldPDG.l2ChainId());

        // If the old FaultDisputeGame exists, we expect it to be upgraded. Check same as above.
        if (address(oldFDG) != address(0)) {
            assertEq(ISemver(address(fdg)).version(), "1.5.0");
            assertEq(address(fdg.vm()), impls.mipsImpl);
            assertEq(fdg.l2ChainId(), oldFDG.l2ChainId());
        }

        // Make sure that the SystemConfig is upgraded to the right version. It must also have the
        // right l2ChainId and must be properly initialized.
        assertEq(ISemver(address(systemConfig)).version(), "3.0.0");
        assertEq(impls.systemConfigImpl, EIP1967Helper.getImplementation(address(systemConfig)));
        assertEq(systemConfig.l2ChainId(), l2ChainId);
        DeployUtils.assertInitialized({ _contractAddress: address(systemConfig), _isProxy: true, _slot: 0, _offset: 0 });

        // Make sure that the OptimismPortal is upgraded to the right version. It must also have a
        // reference to the new AnchorStateRegistry.
        assertEq(ISemver(address(optimismPortal2)).version(), "4.1.0");
        assertEq(impls.optimismPortalImpl, EIP1967Helper.getImplementation(address(optimismPortal2)));
        assertEq(address(optimismPortal2.anchorStateRegistry()), address(newAsrProxy));
        DeployUtils.assertInitialized({
            _contractAddress: address(optimismPortal2),
            _isProxy: true,
            _slot: 0,
            _offset: 0
        });

        // Make sure the new AnchorStateRegistry has the right version and is initialized.
        assertEq(ISemver(address(newAsrProxy)).version(), "3.1.0");
        vm.prank(address(proxyAdmin));
        assertEq(IProxy(payable(newAsrProxy)).admin(), address(proxyAdmin));
        DeployUtils.assertInitialized({ _contractAddress: address(newAsrProxy), _isProxy: true, _slot: 0, _offset: 0 });
    }

    function runUpgradeTestAndChecks(address _delegateCaller) public {
        // TODO(#14691): Remove this function once Upgrade 15 is deployed on Mainnet.
        runUpgrade13UpgradeAndChecks(_delegateCaller);
        // TODO(#14691): Remove this function once Upgrade 15 is deployed on Mainnet.
        runUpgrade14UpgradeAndChecks(_delegateCaller);
        runUpgrade15UpgradeAndChecks(_delegateCaller);
    }
}

contract OPContractsManager_Upgrade_Test is OPContractsManager_Upgrade_Harness {
    function test_upgradeOPChainOnly_succeeds() public {
        skipIfNotOpFork("test_upgradeOPChainOnly_succeeds");
        // Run the upgrade test and checks
        runUpgradeTestAndChecks(upgrader);
    }

    function test_isRcFalseAfterCalledByUpgrader_works() public {
        skipIfNotOpFork("test_isRcFalseAfterCalledByUpgrader_works");
        assertTrue(opcm.isRC());
        bytes memory releaseBytes = bytes(opcm.l1ContractsRelease());
        assertEq(Bytes.slice(releaseBytes, releaseBytes.length - 3, 3), "-rc", "release should end with '-rc'");

        runUpgradeTestAndChecks(upgrader);

        assertFalse(opcm.isRC(), "isRC should be false");
        releaseBytes = bytes(opcm.l1ContractsRelease());
        assertNotEq(Bytes.slice(releaseBytes, releaseBytes.length - 3, 3), "-rc", "release should not end with '-rc'");
    }

    function testFuzz_upgrade_nonUpgradeControllerDelegatecallerShouldNotSetIsRCToFalse_works(
        address _nonUpgradeController
    )
        public
    {
        skipIfNotOpFork("testFuzz_upgrade_nonUpgradeControllerDelegatecallerShouldNotSetIsRCToFalse_works");
        if (
            _nonUpgradeController == upgrader || _nonUpgradeController == address(0)
                || _nonUpgradeController < address(0x4200000000000000000000000000000000000000)
                || _nonUpgradeController > address(0x4200000000000000000000000000000000000800)
                || _nonUpgradeController == address(vm)
                || _nonUpgradeController == 0x000000000000000000636F6e736F6c652e6c6f67
                || _nonUpgradeController == 0x4e59b44847b379578588920cA78FbF26c0B4956C
        ) {
            _nonUpgradeController = makeAddr("nonUpgradeController");
        }

        // Set the proxy admin owner to be the non-upgrade controller
        vm.store(
            address(proxyAdmin),
            bytes32(ForgeArtifacts.getSlot("ProxyAdmin", "_owner").slot),
            bytes32(uint256(uint160(_nonUpgradeController)))
        );
        vm.store(
            address(disputeGameFactory),
            bytes32(ForgeArtifacts.getSlot("DisputeGameFactory", "_owner").slot),
            bytes32(uint256(uint160(_nonUpgradeController)))
        );

        // Run the upgrade test and checks
        runUpgradeTestAndChecks(_nonUpgradeController);
    }

    function test_upgrade_duplicateL2ChainId_succeeds() public {
        skipIfNotOpFork("test_upgrade_duplicateL2ChainId_succeeds");

        // Deploy a new OPChain with the same L2 chain ID as the current OPChain
        Deploy deploy = Deploy(address(uint160(uint256(keccak256(abi.encode("optimism.deploy"))))));
        IOPContractsManager.DeployInput memory deployInput = deploy.getDeployInput();
        deployInput.l2ChainId = l2ChainId;
        deployInput.saltMixer = "v2.0.0";
        opcm.deploy(deployInput);

        // Try to upgrade the current OPChain
        runUpgradeTestAndChecks(upgrader);
    }

    /// @notice Tests that the absolute prestate can be overridden using the upgrade config.
    function test_upgrade_absolutePrestateOverride_succeeds() public {
        // Run Upgrade 13 and 14 to get us to a state where we can run Upgrade 15.
        // Can remove these two calls as Upgrade 13 and 14 are executed in prod.
        runUpgrade13UpgradeAndChecks(upgrader);
        runUpgrade14UpgradeAndChecks(upgrader);

        // Get the pdg and fdg before the upgrade
        Claim pdgPrestateBefore = IPermissionedDisputeGame(
            address(disputeGameFactory.gameImpls(GameTypes.PERMISSIONED_CANNON))
        ).absolutePrestate();
        Claim fdgPrestateBefore =
            IFaultDisputeGame(address(disputeGameFactory.gameImpls(GameTypes.CANNON))).absolutePrestate();

        // Assert that the prestate is not zero.
        assertNotEq(pdgPrestateBefore.raw(), bytes32(0));
        assertNotEq(fdgPrestateBefore.raw(), bytes32(0));

        // Set the absolute prestate input to something non-zero.
        opChainConfigs[0].absolutePrestate = Claim.wrap(bytes32(uint256(1)));

        // Now run Upgrade 15.
        runUpgrade15UpgradeAndChecks(upgrader);

        // Get the absolute prestate after the upgrade
        Claim pdgPrestateAfter = IPermissionedDisputeGame(
            address(disputeGameFactory.gameImpls(GameTypes.PERMISSIONED_CANNON))
        ).absolutePrestate();
        Claim fdgPrestateAfter =
            IFaultDisputeGame(address(disputeGameFactory.gameImpls(GameTypes.CANNON))).absolutePrestate();

        // Assert that the absolute prestate is the non-zero value we set.
        assertEq(pdgPrestateAfter.raw(), bytes32(uint256(1)));
        assertEq(fdgPrestateAfter.raw(), bytes32(uint256(1)));
    }

    /// @notice Tests that the old absolute prestate is used if the upgrade config does not set an
    ///         absolute prestate.
    function test_upgrade_absolutePrestateNotSet_succeeds() public {
        // Run Upgrade 13 and 14 to get us to a state where we can run Upgrade 15.
        // Can remove these two calls as Upgrade 13 and 14 are executed in prod.
        runUpgrade13UpgradeAndChecks(upgrader);
        runUpgrade14UpgradeAndChecks(upgrader);

        // Get the pdg and fdg before the upgrade
        Claim pdgPrestateBefore = IPermissionedDisputeGame(
            address(disputeGameFactory.gameImpls(GameTypes.PERMISSIONED_CANNON))
        ).absolutePrestate();
        Claim fdgPrestateBefore =
            IFaultDisputeGame(address(disputeGameFactory.gameImpls(GameTypes.CANNON))).absolutePrestate();

        // Assert that the prestate is not zero.
        assertNotEq(pdgPrestateBefore.raw(), bytes32(0));
        assertNotEq(fdgPrestateBefore.raw(), bytes32(0));

        // Set the absolute prestate input to zero.
        opChainConfigs[0].absolutePrestate = Claim.wrap(bytes32(0));

        // Now run Upgrade 15.
        runUpgrade15UpgradeAndChecks(upgrader);

        // Get the absolute prestate after the upgrade
        Claim pdgPrestateAfter = IPermissionedDisputeGame(
            address(disputeGameFactory.gameImpls(GameTypes.PERMISSIONED_CANNON))
        ).absolutePrestate();
        Claim fdgPrestateAfter =
            IFaultDisputeGame(address(disputeGameFactory.gameImpls(GameTypes.CANNON))).absolutePrestate();

        // Assert that the absolute prestate is the same as before the upgrade.
        assertEq(pdgPrestateAfter.raw(), pdgPrestateBefore.raw());
        assertEq(fdgPrestateAfter.raw(), fdgPrestateBefore.raw());
    }
}

contract OPContractsManager_Upgrade_TestFails is OPContractsManager_Upgrade_Harness {
    // Upgrade to U14 first
    function setUp() public override {
        skipIfNotOpFork("test_upgrade_notDelegateCalled_reverts");
        super.setUp();
        runUpgrade13UpgradeAndChecks(upgrader);
    }

    function test_upgrade_notDelegateCalled_reverts() public {
        vm.prank(upgrader);
        vm.expectRevert(IOPContractsManager.OnlyDelegatecall.selector);
        opcm.upgrade(opChainConfigs);
    }

    function test_upgrade_notProxyAdminOwner_reverts() public {
        address delegateCaller = makeAddr("delegateCaller");
        vm.etch(delegateCaller, vm.getDeployedCode("test/mocks/Callers.sol:DelegateCaller"));

        assertNotEq(superchainProxyAdmin.owner(), delegateCaller);
        assertNotEq(proxyAdmin.owner(), delegateCaller);

        vm.expectRevert("Ownable: caller is not the owner");
        DelegateCaller(delegateCaller).dcForward(
            address(opcm), abi.encodeCall(IOPContractsManager.upgrade, (opChainConfigs))
        );
    }

    /// @notice Tests that upgrade reverts when absolutePrestate is zero and the existing game also
    ///         has an absolute prestate of zero.
    function test_upgrade_absolutePrestateNotSet_reverts() public {
        // Set the config to try to update the absolutePrestate to zero.
        opChainConfigs[0].absolutePrestate = Claim.wrap(bytes32(0));

        // Get the address of the PermissionedDisputeGame.
        IPermissionedDisputeGame pdg =
            IPermissionedDisputeGame(address(disputeGameFactory.gameImpls(GameTypes.PERMISSIONED_CANNON)));

        // Mock the PDG to return a prestate of zero.
        vm.mockCall(
            address(pdg),
            abi.encodeCall(IPermissionedDisputeGame.absolutePrestate, ()),
            abi.encode(Claim.wrap(bytes32(0)))
        );

        // Expect the upgrade to revert with PrestateNotSet.
        vm.expectRevert(IOPContractsManager.PrestateNotSet.selector);
        DelegateCaller(upgrader).dcForward(address(opcm), abi.encodeCall(IOPContractsManager.upgrade, (opChainConfigs)));
    }
}

contract OPContractsManager_SetRC_Test is OPContractsManager_Upgrade_Harness {
    /// @notice Tests the setRC function can be set by the upgrade controller.
    function test_setRC_succeeds(bool _isRC) public {
        skipIfNotOpFork("test_setRC_succeeds");

        vm.prank(upgrader);

        opcm.setRC(_isRC);
        assertTrue(opcm.isRC() == _isRC, "isRC should be true");
        bytes memory releaseBytes = bytes(opcm.l1ContractsRelease());
        if (_isRC) {
            assertEq(Bytes.slice(releaseBytes, releaseBytes.length - 3, 3), "-rc", "release should end with '-rc'");
        } else {
            assertNotEq(
                Bytes.slice(releaseBytes, releaseBytes.length - 3, 3), "-rc", "release should not end with '-rc'"
            );
        }
    }

    /// @notice Tests the setRC function can not be set by non-upgrade controller.
    function test_setRC_nonUpgradeController_reverts(address _nonUpgradeController) public {
        // Disallow the upgrade controller to have code, or be a 'special' address.
        if (
            _nonUpgradeController == upgrader || _nonUpgradeController == address(0)
                || _nonUpgradeController < address(0x4200000000000000000000000000000000000000)
                || _nonUpgradeController > address(0x4200000000000000000000000000000000000800)
                || _nonUpgradeController == address(vm)
                || _nonUpgradeController == 0x000000000000000000636F6e736F6c652e6c6f67
                || _nonUpgradeController == 0x4e59b44847b379578588920cA78FbF26c0B4956C
                || _nonUpgradeController.code.length > 0
        ) {
            _nonUpgradeController = makeAddr("nonUpgradeController");
        }

        vm.prank(_nonUpgradeController);

        vm.expectRevert(IOPContractsManager.OnlyUpgradeController.selector);
        opcm.setRC(true);
    }
}

contract OPContractsManager_AddGameType_Test is Test {
    IOPContractsManager internal opcm;

    IOPContractsManager.DeployOutput internal chainDeployOutput;

    event GameTypeAdded(
        uint256 indexed l2ChainId, GameType indexed gameType, IDisputeGame newDisputeGame, IDisputeGame oldDisputeGame
    );

    function setUp() public {
        ISuperchainConfig superchainConfigProxy = ISuperchainConfig(makeAddr("superchainConfig"));
        IProtocolVersions protocolVersionsProxy = IProtocolVersions(makeAddr("protocolVersions"));
        IProxyAdmin superchainProxyAdmin = IProxyAdmin(makeAddr("superchainProxyAdmin"));
        bytes32 salt = hex"01";
        IOPContractsManager.Blueprints memory blueprints;
        (blueprints.addressManager,) = Blueprint.create(vm.getCode("AddressManager"), salt);
        (blueprints.proxy,) = Blueprint.create(vm.getCode("Proxy"), salt);
        (blueprints.proxyAdmin,) = Blueprint.create(vm.getCode("ProxyAdmin"), salt);
        (blueprints.l1ChugSplashProxy,) = Blueprint.create(vm.getCode("L1ChugSplashProxy"), salt);
        (blueprints.resolvedDelegateProxy,) = Blueprint.create(vm.getCode("ResolvedDelegateProxy"), salt);
        (blueprints.permissionedDisputeGame1, blueprints.permissionedDisputeGame2) =
            Blueprint.create(vm.getCode("PermissionedDisputeGame"), salt);
        (blueprints.permissionlessDisputeGame1, blueprints.permissionlessDisputeGame2) =
            Blueprint.create(vm.getCode("FaultDisputeGame"), salt);

        IPreimageOracle oracle = IPreimageOracle(
            DeployUtils.create1({
                _name: "PreimageOracle",
                _args: DeployUtils.encodeConstructor(abi.encodeCall(IPreimageOracle.__constructor__, (126000, 86400)))
            })
        );

        IOPContractsManager.Implementations memory impls = IOPContractsManager.Implementations({
            superchainConfigImpl: DeployUtils.create1({
                _name: "SuperchainConfig",
                _args: DeployUtils.encodeConstructor(abi.encodeCall(ISuperchainConfig.__constructor__, ()))
            }),
            protocolVersionsImpl: DeployUtils.create1({
                _name: "ProtocolVersions",
                _args: DeployUtils.encodeConstructor(abi.encodeCall(IProtocolVersions.__constructor__, ()))
            }),
            l1ERC721BridgeImpl: DeployUtils.create1({
                _name: "L1ERC721Bridge",
                _args: DeployUtils.encodeConstructor(abi.encodeCall(IL1ERC721Bridge.__constructor__, ()))
            }),
            optimismPortalImpl: DeployUtils.create1({
                _name: "OptimismPortal2",
                _args: DeployUtils.encodeConstructor(abi.encodeCall(IOptimismPortal2.__constructor__, (1)))
            }),
            ethLockboxImpl: DeployUtils.create1({
                _name: "ETHLockbox",
                _args: DeployUtils.encodeConstructor(abi.encodeCall(IETHLockbox.__constructor__, ()))
            }),
            systemConfigImpl: DeployUtils.create1({
                _name: "SystemConfig",
                _args: DeployUtils.encodeConstructor(abi.encodeCall(ISystemConfig.__constructor__, ()))
            }),
            optimismMintableERC20FactoryImpl: DeployUtils.create1({
                _name: "OptimismMintableERC20Factory",
                _args: DeployUtils.encodeConstructor(abi.encodeCall(IOptimismMintableERC20Factory.__constructor__, ()))
            }),
            l1CrossDomainMessengerImpl: DeployUtils.create1({
                _name: "L1CrossDomainMessenger",
                _args: DeployUtils.encodeConstructor(abi.encodeCall(IL1CrossDomainMessenger.__constructor__, ()))
            }),
            l1StandardBridgeImpl: DeployUtils.create1({
                _name: "L1StandardBridge",
                _args: DeployUtils.encodeConstructor(abi.encodeCall(IL1StandardBridge.__constructor__, ()))
            }),
            disputeGameFactoryImpl: DeployUtils.create1({
                _name: "DisputeGameFactory",
                _args: DeployUtils.encodeConstructor(abi.encodeCall(IDisputeGameFactory.__constructor__, ()))
            }),
            anchorStateRegistryImpl: DeployUtils.create1({
                _name: "AnchorStateRegistry",
                _args: DeployUtils.encodeConstructor(abi.encodeCall(IAnchorStateRegistry.__constructor__, (1)))
            }),
            delayedWETHImpl: DeployUtils.create1({
                _name: "DelayedWETH",
                _args: DeployUtils.encodeConstructor(abi.encodeCall(IDelayedWETH.__constructor__, (3)))
            }),
            mipsImpl: DeployUtils.create1({
                _name: "MIPS64",
                _args: DeployUtils.encodeConstructor(abi.encodeCall(IMIPS.__constructor__, (oracle)))
            })
        });

        vm.etch(address(superchainConfigProxy), hex"01");
        vm.etch(address(protocolVersionsProxy), hex"01");

        IOPContractsManagerGameTypeAdder opcmGameTypeAdder = IOPContractsManagerGameTypeAdder(
            DeployUtils.createDeterministic({
                _name: "OPContractsManagerGameTypeAdder",
                _args: DeployUtils.encodeConstructor(
                    abi.encodeCall(
                        IOPContractsManagerGameTypeAdder.__constructor__,
                        (
                            IOPContractsManagerContractsContainer(
                                DeployUtils.createDeterministic({
                                    _name: "OPContractsManagerContractsContainer",
                                    _args: DeployUtils.encodeConstructor(
                                        abi.encodeCall(
                                            IOPContractsManagerContractsContainer.__constructor__, (blueprints, impls)
                                        )
                                    ),
                                    _salt: DeployUtils.DEFAULT_SALT
                                })
                            )
                        )
                    )
                ),
                _salt: DeployUtils.DEFAULT_SALT
            })
        );

        IOPContractsManagerDeployer opcmDeployer = IOPContractsManagerDeployer(
            DeployUtils.createDeterministic({
                _name: "OPContractsManagerDeployer",
                _args: DeployUtils.encodeConstructor(
                    abi.encodeCall(IOPContractsManagerDeployer.__constructor__, (opcmGameTypeAdder.contractsContainer()))
                ),
                _salt: DeployUtils.DEFAULT_SALT
            })
        );

        IOPContractsManagerUpgrader opcmUpgrader = IOPContractsManagerUpgrader(
            DeployUtils.createDeterministic({
                _name: "OPContractsManagerUpgrader",
                _args: DeployUtils.encodeConstructor(
                    abi.encodeCall(IOPContractsManagerUpgrader.__constructor__, (opcmGameTypeAdder.contractsContainer()))
                ),
                _salt: DeployUtils.DEFAULT_SALT
            })
        );

        opcm = IOPContractsManager(
            DeployUtils.createDeterministic({
                _name: "OPContractsManager",
                _args: DeployUtils.encodeConstructor(
                    abi.encodeCall(
                        IOPContractsManager.__constructor__,
                        (
                            opcmGameTypeAdder,
                            opcmDeployer,
                            opcmUpgrader,
                            superchainConfigProxy,
                            protocolVersionsProxy,
                            superchainProxyAdmin,
                            "dev",
                            address(this)
                        )
                    )
                ),
                _salt: DeployUtils.DEFAULT_SALT
            })
        );

        chainDeployOutput = opcm.deploy(
            IOPContractsManager.DeployInput({
                roles: IOPContractsManager.Roles({
                    opChainProxyAdminOwner: address(this),
                    systemConfigOwner: address(this),
                    batcher: address(this),
                    unsafeBlockSigner: address(this),
                    proposer: address(this),
                    challenger: address(this)
                }),
                basefeeScalar: 1,
                blobBasefeeScalar: 1,
                startingAnchorRoot: abi.encode(
                    Proposal({
                        root: Hash.wrap(0xdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef),
                        l2SequenceNumber: 0
                    })
                ),
                l2ChainId: 100,
                saltMixer: "hello",
                gasLimit: 30_000_000,
                disputeGameType: GameType.wrap(1),
                disputeAbsolutePrestate: Claim.wrap(
                    bytes32(hex"038512e02c4c3f7bdaec27d00edf55b7155e0905301e1a88083e4e0a6764d54c")
                ),
                disputeMaxGameDepth: 73,
                disputeSplitDepth: 30,
                disputeClockExtension: Duration.wrap(10800),
                disputeMaxClockDuration: Duration.wrap(302400)
            })
        );
    }

    function test_addGameType_permissioned_succeeds() public {
        IOPContractsManager.AddGameInput memory input = newGameInputFactory(true);
        IOPContractsManager.AddGameOutput memory output = addGameType(input);
        assertValidGameType(input, output);
        IPermissionedDisputeGame newPDG = IPermissionedDisputeGame(address(output.faultDisputeGame));
        IPermissionedDisputeGame oldPDG = chainDeployOutput.permissionedDisputeGame;
        assertEq(newPDG.proposer(), oldPDG.proposer(), "proposer mismatch");
        assertEq(newPDG.challenger(), oldPDG.challenger(), "challenger mismatch");
    }

    function test_addGameType_permissionless_succeeds() public {
        IOPContractsManager.AddGameInput memory input = newGameInputFactory(false);
        IOPContractsManager.AddGameOutput memory output = addGameType(input);
        assertValidGameType(input, output);
        IPermissionedDisputeGame notPDG = IPermissionedDisputeGame(address(output.faultDisputeGame));
        vm.expectRevert(); // nosemgrep: sol-safety-expectrevert-no-args
        notPDG.proposer();
    }

    function test_addGameType_reusedDelayedWETH_succeeds() public {
        IDelayedWETH delayedWETH = IDelayedWETH(
            payable(
                address(
                    DeployUtils.create1({
                        _name: "DelayedWETH",
                        _args: DeployUtils.encodeConstructor(abi.encodeCall(IDelayedWETH.__constructor__, (1)))
                    })
                )
            )
        );
        vm.etch(address(delayedWETH), hex"01");
        IOPContractsManager.AddGameInput memory input = newGameInputFactory(false);
        input.delayedWETH = delayedWETH;
        IOPContractsManager.AddGameOutput memory output = addGameType(input);
        assertValidGameType(input, output);
        assertEq(address(output.delayedWETH), address(delayedWETH), "delayedWETH address mismatch");
    }

    function test_addGameType_outOfOrderInputs_reverts() public {
        IOPContractsManager.AddGameInput memory input1 = newGameInputFactory(false);
        input1.disputeGameType = GameType.wrap(2);
        IOPContractsManager.AddGameInput memory input2 = newGameInputFactory(false);
        input2.disputeGameType = GameType.wrap(1);
        IOPContractsManager.AddGameInput[] memory inputs = new IOPContractsManager.AddGameInput[](2);
        inputs[0] = input1;
        inputs[1] = input2;

        // For the sake of completeness, we run the call again to validate the success behavior.
        (bool success,) = address(opcm).delegatecall(abi.encodeCall(IOPContractsManager.addGameType, (inputs)));
        assertFalse(success, "addGameType should have failed");
    }

    function test_addGameType_duplicateGameType_reverts() public {
        IOPContractsManager.AddGameInput memory input = newGameInputFactory(false);
        IOPContractsManager.AddGameInput[] memory inputs = new IOPContractsManager.AddGameInput[](2);
        inputs[0] = input;
        inputs[1] = input;

        // See test above for why we run the call twice.
        (bool success, bytes memory revertData) =
            address(opcm).delegatecall(abi.encodeCall(IOPContractsManager.addGameType, (inputs)));
        assertFalse(success, "addGameType should have failed");
        assertEq(bytes4(revertData), IOPContractsManager.InvalidGameConfigs.selector, "revertData mismatch");
    }

    function test_addGameType_zeroLengthInput_reverts() public {
        IOPContractsManager.AddGameInput[] memory inputs = new IOPContractsManager.AddGameInput[](0);

        (bool success, bytes memory revertData) =
            address(opcm).delegatecall(abi.encodeCall(IOPContractsManager.addGameType, (inputs)));
        assertFalse(success, "addGameType should have failed");
        assertEq(bytes4(revertData), IOPContractsManager.InvalidGameConfigs.selector, "revertData mismatch");
    }

    function test_addGameType_notDelegateCall_reverts() public {
        IOPContractsManager.AddGameInput memory input = newGameInputFactory(true);
        IOPContractsManager.AddGameInput[] memory inputs = new IOPContractsManager.AddGameInput[](1);
        inputs[0] = input;

        vm.expectRevert(IOPContractsManager.OnlyDelegatecall.selector);
        opcm.addGameType(inputs);
    }

    function addGameType(IOPContractsManager.AddGameInput memory input)
        internal
        returns (IOPContractsManager.AddGameOutput memory)
    {
        IOPContractsManager.AddGameInput[] memory inputs = new IOPContractsManager.AddGameInput[](1);
        inputs[0] = input;

        uint256 l2ChainId = IFaultDisputeGame(
            address(IDisputeGameFactory(input.systemConfig.disputeGameFactory()).gameImpls(GameType.wrap(1)))
        ).l2ChainId();

        // Expect the GameTypeAdded event to be emitted.
        vm.expectEmit(true, true, false, false, address(this));
        emit GameTypeAdded(
            l2ChainId, input.disputeGameType, IDisputeGame(payable(address(0))), IDisputeGame(payable(address(0)))
        );
        (bool success, bytes memory rawGameOut) =
            address(opcm).delegatecall(abi.encodeCall(IOPContractsManager.addGameType, (inputs)));
        assertTrue(success, "addGameType failed");

        IOPContractsManager.AddGameOutput[] memory addGameOutAll =
            abi.decode(rawGameOut, (IOPContractsManager.AddGameOutput[]));
        return addGameOutAll[0];
    }

    function newGameInputFactory(bool permissioned) internal view returns (IOPContractsManager.AddGameInput memory) {
        return IOPContractsManager.AddGameInput({
            saltMixer: "hello",
            systemConfig: chainDeployOutput.systemConfigProxy,
            proxyAdmin: chainDeployOutput.opChainProxyAdmin,
            delayedWETH: IDelayedWETH(payable(address(0))),
            disputeGameType: GameType.wrap(2000),
            disputeAbsolutePrestate: Claim.wrap(bytes32(hex"deadbeef1234")),
            disputeMaxGameDepth: 73,
            disputeSplitDepth: 30,
            disputeClockExtension: Duration.wrap(10800),
            disputeMaxClockDuration: Duration.wrap(302400),
            initialBond: 1 ether,
            vm: IBigStepper(address(opcm.implementations().mipsImpl)),
            permissioned: permissioned
        });
    }

    function assertValidGameType(
        IOPContractsManager.AddGameInput memory agi,
        IOPContractsManager.AddGameOutput memory ago
    )
        internal
        view
    {
        // Check the config for the game itself
        assertEq(ago.faultDisputeGame.gameType().raw(), agi.disputeGameType.raw(), "gameType mismatch");
        assertEq(
            ago.faultDisputeGame.absolutePrestate().raw(),
            agi.disputeAbsolutePrestate.raw(),
            "absolutePrestate mismatch"
        );
        assertEq(ago.faultDisputeGame.maxGameDepth(), agi.disputeMaxGameDepth, "maxGameDepth mismatch");
        assertEq(ago.faultDisputeGame.splitDepth(), agi.disputeSplitDepth, "splitDepth mismatch");
        assertEq(
            ago.faultDisputeGame.clockExtension().raw(), agi.disputeClockExtension.raw(), "clockExtension mismatch"
        );
        assertEq(
            ago.faultDisputeGame.maxClockDuration().raw(),
            agi.disputeMaxClockDuration.raw(),
            "maxClockDuration mismatch"
        );
        assertEq(address(ago.faultDisputeGame.vm()), address(agi.vm), "vm address mismatch");
        assertEq(address(ago.faultDisputeGame.weth()), address(ago.delayedWETH), "delayedWETH address mismatch");
        assertEq(
            address(ago.faultDisputeGame.anchorStateRegistry()),
            address(chainDeployOutput.anchorStateRegistryProxy),
            "ASR address mismatch"
        );

        // Check the DGF
        assertEq(
            chainDeployOutput.disputeGameFactoryProxy.gameImpls(agi.disputeGameType).gameType().raw(),
            agi.disputeGameType.raw(),
            "gameType mismatch"
        );
        assertEq(
            address(chainDeployOutput.disputeGameFactoryProxy.gameImpls(agi.disputeGameType)),
            address(ago.faultDisputeGame),
            "gameImpl address mismatch"
        );
        assertEq(address(ago.faultDisputeGame.weth()), address(ago.delayedWETH), "weth address mismatch");
        assertEq(
            chainDeployOutput.disputeGameFactoryProxy.initBonds(agi.disputeGameType), agi.initialBond, "bond mismatch"
        );
    }
}

contract OPContractsManager_UpdatePrestate_Test is Test {
    IOPContractsManager internal opcm;
    IOPContractsManager internal prestateUpdater;

    OPContractsManager.OpChainConfig[] internal opChainConfigs;
    OPContractsManager.AddGameInput[] internal gameInput;

    IOPContractsManager.DeployOutput internal chainDeployOutput;

    function setUp() public {
        IProxyAdmin superchainProxyAdmin = IProxyAdmin(makeAddr("superchainProxyAdmin"));
        ISuperchainConfig superchainConfigProxy = ISuperchainConfig(makeAddr("superchainConfig"));
        IProtocolVersions protocolVersionsProxy = IProtocolVersions(makeAddr("protocolVersions"));
        bytes32 salt = hex"01";
        IOPContractsManager.Blueprints memory blueprints;

        (blueprints.addressManager,) = Blueprint.create(vm.getCode("AddressManager"), salt);
        (blueprints.proxy,) = Blueprint.create(vm.getCode("Proxy"), salt);
        (blueprints.proxyAdmin,) = Blueprint.create(vm.getCode("ProxyAdmin"), salt);
        (blueprints.l1ChugSplashProxy,) = Blueprint.create(vm.getCode("L1ChugSplashProxy"), salt);
        (blueprints.resolvedDelegateProxy,) = Blueprint.create(vm.getCode("ResolvedDelegateProxy"), salt);
        (blueprints.permissionedDisputeGame1, blueprints.permissionedDisputeGame2) =
            Blueprint.create(vm.getCode("PermissionedDisputeGame"), salt);
        (blueprints.permissionlessDisputeGame1, blueprints.permissionlessDisputeGame2) =
            Blueprint.create(vm.getCode("FaultDisputeGame"), salt);

        IPreimageOracle oracle = IPreimageOracle(
            DeployUtils.create1({
                _name: "PreimageOracle",
                _args: DeployUtils.encodeConstructor(abi.encodeCall(IPreimageOracle.__constructor__, (126000, 86400)))
            })
        );

        IOPContractsManager.Implementations memory impls = IOPContractsManager.Implementations({
            superchainConfigImpl: DeployUtils.create1({
                _name: "SuperchainConfig",
                _args: DeployUtils.encodeConstructor(abi.encodeCall(ISuperchainConfig.__constructor__, ()))
            }),
            protocolVersionsImpl: DeployUtils.create1({
                _name: "ProtocolVersions",
                _args: DeployUtils.encodeConstructor(abi.encodeCall(IProtocolVersions.__constructor__, ()))
            }),
            l1ERC721BridgeImpl: DeployUtils.create1({
                _name: "L1ERC721Bridge",
                _args: DeployUtils.encodeConstructor(abi.encodeCall(IL1ERC721Bridge.__constructor__, ()))
            }),
            optimismPortalImpl: DeployUtils.create1({
                _name: "OptimismPortal2",
                _args: DeployUtils.encodeConstructor(abi.encodeCall(IOptimismPortal2.__constructor__, (1)))
            }),
            ethLockboxImpl: DeployUtils.create1({
                _name: "ETHLockbox",
                _args: DeployUtils.encodeConstructor(abi.encodeCall(IETHLockbox.__constructor__, ()))
            }),
            systemConfigImpl: DeployUtils.create1({
                _name: "SystemConfig",
                _args: DeployUtils.encodeConstructor(abi.encodeCall(ISystemConfig.__constructor__, ()))
            }),
            optimismMintableERC20FactoryImpl: DeployUtils.create1({
                _name: "OptimismMintableERC20Factory",
                _args: DeployUtils.encodeConstructor(abi.encodeCall(IOptimismMintableERC20Factory.__constructor__, ()))
            }),
            l1CrossDomainMessengerImpl: DeployUtils.create1({
                _name: "L1CrossDomainMessenger",
                _args: DeployUtils.encodeConstructor(abi.encodeCall(IL1CrossDomainMessenger.__constructor__, ()))
            }),
            l1StandardBridgeImpl: DeployUtils.create1({
                _name: "L1StandardBridge",
                _args: DeployUtils.encodeConstructor(abi.encodeCall(IL1StandardBridge.__constructor__, ()))
            }),
            disputeGameFactoryImpl: DeployUtils.create1({
                _name: "DisputeGameFactory",
                _args: DeployUtils.encodeConstructor(abi.encodeCall(IDisputeGameFactory.__constructor__, ()))
            }),
            anchorStateRegistryImpl: DeployUtils.create1({
                _name: "AnchorStateRegistry",
                _args: DeployUtils.encodeConstructor(abi.encodeCall(IAnchorStateRegistry.__constructor__, (1)))
            }),
            delayedWETHImpl: DeployUtils.create1({
                _name: "DelayedWETH",
                _args: DeployUtils.encodeConstructor(abi.encodeCall(IDelayedWETH.__constructor__, (3)))
            }),
            mipsImpl: DeployUtils.create1({
                _name: "MIPS",
                _args: DeployUtils.encodeConstructor(abi.encodeCall(IMIPS.__constructor__, (oracle)))
            })
        });

        vm.etch(address(superchainConfigProxy), hex"01");
        vm.etch(address(protocolVersionsProxy), hex"01");

        IOPContractsManagerContractsContainer container = IOPContractsManagerContractsContainer(
            DeployUtils.createDeterministic({
                _name: "OPContractsManagerContractsContainer",
                _args: DeployUtils.encodeConstructor(
                    abi.encodeCall(IOPContractsManagerContractsContainer.__constructor__, (blueprints, impls))
                ),
                _salt: DeployUtils.DEFAULT_SALT
            })
        );

        opcm = IOPContractsManager(
            DeployUtils.createDeterministic({
                _name: "OPContractsManager",
                _args: DeployUtils.encodeConstructor(
                    abi.encodeCall(
                        IOPContractsManager.__constructor__,
                        (
                            IOPContractsManagerGameTypeAdder(
                                DeployUtils.createDeterministic({
                                    _name: "OPContractsManagerGameTypeAdder",
                                    _args: DeployUtils.encodeConstructor(
                                        abi.encodeCall(IOPContractsManagerGameTypeAdder.__constructor__, (container))
                                    ),
                                    _salt: DeployUtils.DEFAULT_SALT
                                })
                            ),
                            IOPContractsManagerDeployer(
                                DeployUtils.createDeterministic({
                                    _name: "OPContractsManagerDeployer",
                                    _args: DeployUtils.encodeConstructor(
                                        abi.encodeCall(IOPContractsManagerDeployer.__constructor__, (container))
                                    ),
                                    _salt: DeployUtils.DEFAULT_SALT
                                })
                            ),
                            IOPContractsManagerUpgrader(
                                DeployUtils.createDeterministic({
                                    _name: "OPContractsManagerUpgrader",
                                    _args: DeployUtils.encodeConstructor(
                                        abi.encodeCall(IOPContractsManagerUpgrader.__constructor__, (container))
                                    ),
                                    _salt: DeployUtils.DEFAULT_SALT
                                })
                            ),
                            superchainConfigProxy,
                            protocolVersionsProxy,
                            superchainProxyAdmin,
                            "dev",
                            address(this)
                        )
                    )
                ),
                _salt: DeployUtils.DEFAULT_SALT
            })
        );

        chainDeployOutput = opcm.deploy(
            IOPContractsManager.DeployInput({
                roles: IOPContractsManager.Roles({
                    opChainProxyAdminOwner: address(this),
                    systemConfigOwner: address(this),
                    batcher: address(this),
                    unsafeBlockSigner: address(this),
                    proposer: address(this),
                    challenger: address(this)
                }),
                basefeeScalar: 1,
                blobBasefeeScalar: 1,
                startingAnchorRoot: abi.encode(
                    Proposal({
                        root: Hash.wrap(0xdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef),
                        l2SequenceNumber: 0
                    })
                ),
                l2ChainId: 100,
                saltMixer: "hello",
                gasLimit: 30_000_000,
                disputeGameType: GameType.wrap(1),
                disputeAbsolutePrestate: Claim.wrap(
                    bytes32(hex"038512e02c4c3f7bdaec27d00edf55b7155e0905301e1a88083e4e0a6764d54c")
                ),
                disputeMaxGameDepth: 73,
                disputeSplitDepth: 30,
                disputeClockExtension: Duration.wrap(10800),
                disputeMaxClockDuration: Duration.wrap(302400)
            })
        );

        prestateUpdater = opcm;
    }

    function test_semver_works() public view {
        assertNotEq(abi.encode(prestateUpdater.version()), abi.encode(0));
    }

    function test_updatePrestate_pdgOnlyWithValidInput_succeeds() public {
        IOPContractsManager.OpChainConfig[] memory inputs = new IOPContractsManager.OpChainConfig[](1);
        inputs[0] = IOPContractsManager.OpChainConfig(
            chainDeployOutput.systemConfigProxy, chainDeployOutput.opChainProxyAdmin, Claim.wrap(bytes32(hex"ABBA"))
        );
        address proxyAdminOwner = chainDeployOutput.opChainProxyAdmin.owner();

        vm.etch(address(proxyAdminOwner), vm.getDeployedCode("test/mocks/Callers.sol:DelegateCaller"));
        DelegateCaller(proxyAdminOwner).dcForward(
            address(prestateUpdater), abi.encodeCall(IOPContractsManager.updatePrestate, (inputs))
        );

        IPermissionedDisputeGame pdg = IPermissionedDisputeGame(
            address(
                IDisputeGameFactory(chainDeployOutput.systemConfigProxy.disputeGameFactory()).gameImpls(
                    GameTypes.PERMISSIONED_CANNON
                )
            )
        );

        assertEq(pdg.absolutePrestate().raw(), inputs[0].absolutePrestate.raw(), "pdg prestate mismatch");

        // Ensure that the WETH contract is not reverting
        pdg.weth().balanceOf(address(0));
    }

    function test_updatePrestate_bothGamesWithValidInput_succeeds() public {
        // Also add a permissionless game
        IOPContractsManager.AddGameInput memory input = newGameInputFactory({ permissioned: false });
        input.disputeGameType = GameTypes.CANNON;
        addGameType(input);

        IOPContractsManager.OpChainConfig[] memory inputs = new IOPContractsManager.OpChainConfig[](1);
        inputs[0] = IOPContractsManager.OpChainConfig(
            chainDeployOutput.systemConfigProxy, chainDeployOutput.opChainProxyAdmin, Claim.wrap(bytes32(hex"ABBA"))
        );
        address proxyAdminOwner = chainDeployOutput.opChainProxyAdmin.owner();

        vm.etch(address(proxyAdminOwner), vm.getDeployedCode("test/mocks/Callers.sol:DelegateCaller"));
        DelegateCaller(proxyAdminOwner).dcForward(
            address(prestateUpdater), abi.encodeCall(IOPContractsManager.updatePrestate, (inputs))
        );

        IPermissionedDisputeGame pdg = IPermissionedDisputeGame(
            address(
                IDisputeGameFactory(chainDeployOutput.systemConfigProxy.disputeGameFactory()).gameImpls(
                    GameTypes.PERMISSIONED_CANNON
                )
            )
        );
        IPermissionedDisputeGame fdg = IPermissionedDisputeGame(
            address(
                IDisputeGameFactory(chainDeployOutput.systemConfigProxy.disputeGameFactory()).gameImpls(
                    GameTypes.CANNON
                )
            )
        );

        assertEq(pdg.absolutePrestate().raw(), inputs[0].absolutePrestate.raw(), "pdg prestate mismatch");
        assertEq(fdg.absolutePrestate().raw(), inputs[0].absolutePrestate.raw(), "fdg prestate mismatch");

        // Ensure that the WETH contracts are not reverting
        pdg.weth().balanceOf(address(0));
        fdg.weth().balanceOf(address(0));
    }

    function test_updatePrestate_whenPDGPrestateIsZero_reverts() public {
        IOPContractsManager.OpChainConfig[] memory inputs = new IOPContractsManager.OpChainConfig[](1);
        inputs[0] = IOPContractsManager.OpChainConfig({
            systemConfigProxy: chainDeployOutput.systemConfigProxy,
            proxyAdmin: chainDeployOutput.opChainProxyAdmin,
            absolutePrestate: Claim.wrap(bytes32(0))
        });

        address proxyAdminOwner = chainDeployOutput.opChainProxyAdmin.owner();
        vm.etch(address(proxyAdminOwner), vm.getDeployedCode("test/mocks/Callers.sol:DelegateCaller"));

        vm.expectRevert(IOPContractsManager.PrestateRequired.selector);
        DelegateCaller(proxyAdminOwner).dcForward(
            address(prestateUpdater), abi.encodeCall(IOPContractsManager.updatePrestate, (inputs))
        );
    }

    function addGameType(IOPContractsManager.AddGameInput memory input)
        internal
        returns (IOPContractsManager.AddGameOutput memory)
    {
        IOPContractsManager.AddGameInput[] memory inputs = new IOPContractsManager.AddGameInput[](1);
        inputs[0] = input;

        (bool success, bytes memory rawGameOut) =
            address(opcm).delegatecall(abi.encodeCall(IOPContractsManager.addGameType, (inputs)));
        assertTrue(success, "addGameType failed");

        IOPContractsManager.AddGameOutput[] memory addGameOutAll =
            abi.decode(rawGameOut, (IOPContractsManager.AddGameOutput[]));
        return addGameOutAll[0];
    }

    function newGameInputFactory(bool permissioned) internal view returns (IOPContractsManager.AddGameInput memory) {
        return IOPContractsManager.AddGameInput({
            saltMixer: "hello",
            systemConfig: chainDeployOutput.systemConfigProxy,
            proxyAdmin: chainDeployOutput.opChainProxyAdmin,
            delayedWETH: IDelayedWETH(payable(address(0))),
            disputeGameType: GameType.wrap(2000),
            disputeAbsolutePrestate: Claim.wrap(bytes32(hex"deadbeef1234")),
            disputeMaxGameDepth: 73,
            disputeSplitDepth: 30,
            disputeClockExtension: Duration.wrap(10800),
            disputeMaxClockDuration: Duration.wrap(302400),
            initialBond: 1 ether,
            vm: IBigStepper(address(opcm.implementations().mipsImpl)),
            permissioned: permissioned
        });
    }
}
