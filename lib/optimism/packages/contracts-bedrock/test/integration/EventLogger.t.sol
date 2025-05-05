// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { Test } from "forge-std/Test.sol";

import { Identifier as IfaceIdentifier } from "interfaces/L2/ICrossL2Inbox.sol";

import { EventLogger } from "../../src/integration/EventLogger.sol";

import { Predeploys } from "src/libraries/Predeploys.sol";

import { Identifier as ImplIdentifier } from "src/L2/CrossL2Inbox.sol";
import { CrossL2InboxWithSlotWarming as CrossL2Inbox } from "test/L2/CrossL2Inbox.t.sol";

contract EventLogger_Initializer is Test {
    event ExecutingMessage(bytes32 indexed msgHash, ImplIdentifier id);

    EventLogger eventLogger;

    function setUp() public {
        // Deploy EventLogger contract
        eventLogger = new EventLogger();
        vm.label(address(eventLogger), "EventLogger");

        vm.etch(Predeploys.CROSS_L2_INBOX, address(new CrossL2Inbox()).code);
        vm.label(Predeploys.CROSS_L2_INBOX, "CrossL2Inbox");
    }
}

contract EventLoggerTest is EventLogger_Initializer {
    /// @notice Test logging
    function test_emitLog_succeeds(
        uint256 topicCount,
        bytes32 t0,
        bytes32 t1,
        bytes32 t2,
        bytes32 t3,
        bytes memory data
    )
        external
    {
        bytes32[] memory topics = new bytes32[](topicCount % 5);
        if (topics.length == 0) {
            vm.expectEmitAnonymous();
            assembly {
                log0(add(data, 32), mload(data))
            }
        } else if (topics.length == 1) {
            topics[0] = t0;
            vm.expectEmit(false, false, false, true);
            assembly {
                log1(add(data, 32), mload(data), t0)
            }
        } else if (topics.length == 2) {
            topics[0] = t0;
            topics[1] = t1;
            vm.expectEmit(true, false, false, true);
            assembly {
                log2(add(data, 32), mload(data), t0, t1)
            }
        } else if (topics.length == 3) {
            topics[0] = t0;
            topics[1] = t1;
            topics[2] = t2;
            vm.expectEmit(true, true, false, true);
            assembly {
                log3(add(data, 32), mload(data), t0, t1, t2)
            }
        } else if (topics.length == 4) {
            topics[0] = t0;
            topics[1] = t1;
            topics[2] = t2;
            topics[3] = t3;
            vm.expectEmit(true, true, true, true);
            assembly {
                log4(add(data, 32), mload(data), t0, t1, t2, t3)
            }
        }
        eventLogger.emitLog(topics, data);
    }

    /// @notice It should revert if called with 5 topics
    function test_emitLog_5topics_reverts() external {
        bytes32[] memory topics = new bytes32[](5); // 5 or more topics: not possible to log
        bytes memory empty = new bytes(0);
        vm.expectRevert(empty);
        eventLogger.emitLog(topics, empty);
    }

    /// @notice It should succeed with any Identifier
    function test_validateMessage_succeeds(
        address _origin,
        uint64 _blockNumber,
        uint32 _logIndex,
        uint64 _timestamp,
        uint256 _chainId,
        bytes32 _msgHash
    )
        external
    {
        IfaceIdentifier memory idIface = IfaceIdentifier({
            origin: _origin,
            blockNumber: _blockNumber,
            logIndex: _logIndex,
            timestamp: _timestamp,
            chainId: _chainId
        });
        ImplIdentifier memory idImpl = ImplIdentifier({
            origin: _origin,
            blockNumber: _blockNumber,
            logIndex: _logIndex,
            timestamp: _timestamp,
            chainId: _chainId
        });

        address emitter = Predeploys.CROSS_L2_INBOX;

        // Warm the slot for the function to succeed
        bytes32 checksum = CrossL2Inbox(emitter).calculateChecksum(idImpl, _msgHash);
        CrossL2Inbox(emitter).warmSlot(checksum);

        vm.expectEmit(false, false, false, true, emitter);
        emit ExecutingMessage(_msgHash, idImpl);

        eventLogger.validateMessage(idIface, _msgHash);
    }
}
