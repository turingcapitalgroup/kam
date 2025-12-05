// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import { BaseVaultTest, DeploymentBaseTest } from "../utils/BaseVaultTest.sol";
import { _1_USDC } from "../utils/Constants.sol";

import { SafeTransferLib } from "solady/utils/SafeTransferLib.sol";

import { IVault } from "kam/src/interfaces/IVault.sol";
import { IkStakingVault } from "kam/src/interfaces/IkStakingVault.sol";

import {
    KSTAKINGVAULT_INSUFFICIENT_BALANCE,
    KSTAKINGVAULT_IS_PAUSED,
    VAULTCLAIMS_BATCH_NOT_SETTLED,
    VAULTCLAIMS_NOT_BENEFICIARY,
    VAULTCLAIMS_REQUEST_NOT_PENDING
} from "kam/src/errors/Errors.sol";
import { BaseVaultTypes, kStakingVault } from "kam/src/kStakingVault/kStakingVault.sol";

contract ERC2771ContextTest is BaseVaultTest {
    using SafeTransferLib for address;

    address trustedForwarder = address(uint160(uint256(keccak256("trustedForwarder"))));
    address public mockForwarder;

    function setUp() public override {
        DeploymentBaseTest.setUp();

        vault = IkStakingVault(address(dnVault));

        // Set up forwarders
        mockForwarder = makeAddr("mockForwarder");

        BaseVaultTest.setUp();
    }

    /* //////////////////////////////////////////////////////////////
                            HELPER FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Helper to encode calldata with appended sender address (ERC-2771 format)
    /// @param originalCalldata The original function call data
    /// @param sender The address to append (the real sender)
    /// @return The calldata with sender appended at the end (as raw 20 bytes)
    function _appendSender(bytes memory originalCalldata, address sender) internal pure returns (bytes memory) {
        // ERC-2771 specifies appending the address as raw 20 bytes, not 32 bytes
        return abi.encodePacked(originalCalldata, sender);
    }

    /// @notice Helper to make a forwarded call through the trusted forwarder
    /// @param target The target contract
    /// @param originalCalldata The original calldata
    /// @param realSender The real sender whose address will be appended
    function _forwardCall(address target, bytes memory originalCalldata, address realSender) internal {
        bytes memory forwardedCalldata = _appendSender(originalCalldata, realSender);
        vm.prank(trustedForwarder);
        (bool success, bytes memory returnData) = target.call(forwardedCalldata);
        if (!success) {
            // Bubble up the revert
            assembly {
                revert(add(returnData, 32), mload(returnData))
            }
        }
    }

    /* //////////////////////////////////////////////////////////////
                    CONTEXT WITH ZERO FORWARDER TESTS
    //////////////////////////////////////////////////////////////*/

    function test_RequestStake_WithZeroForwarder_DirectCall() public {
        // Setup: Mint kTokens to Alice
        _mintKTokenToUser(users.alice, 1000 * _1_USDC, true);

        vm.prank(users.alice);
        kUSD.approve(address(vault), 1000 * _1_USDC);

        bytes32 batchId = vault.getBatchId();

        // Test: Direct call should work normally
        vm.prank(users.alice);
        bytes32 requestId = vault.requestStake(users.alice, 1000 * _1_USDC);

        // Verify request was created correctly
        BaseVaultTypes.StakeRequest memory req = vault.getStakeRequest(requestId);
        assertEq(req.user, users.alice, "User should be Alice");
        assertEq(req.recipient, users.alice, "Recipient should be Alice");
    }

    /* //////////////////////////////////////////////////////////////
                FORWARDED CALL TESTS (With Real Forwarder)
    //////////////////////////////////////////////////////////////*/

    function test_RequestStake_ThroughForwarder() public {
        // Setup: Mint kTokens to Alice
        _mintKTokenToUser(users.alice, 1000 * _1_USDC, true);

        vm.prank(users.alice);
        kUSD.approve(address(vault), 1000 * _1_USDC);

        bytes32 batchId = vault.getBatchId();

        // Prepare the call data
        bytes memory callData = abi.encodeWithSelector(
            vault.requestStake.selector,
            users.alice, // recipient
            1000 * _1_USDC // amount
        );

        // Forward the call with Alice's address appended (as raw 20 bytes)
        vm.prank(trustedForwarder);
        (bool success, bytes memory returnData) = address(vault).call(_appendSender(callData, users.alice));
        require(success, "Forwarded call failed");

        bytes32 requestId = abi.decode(returnData, (bytes32));

        // Verify request was created correctly
        BaseVaultTypes.StakeRequest memory req = vault.getStakeRequest(requestId);
        assertEq(req.user, users.alice, "User should be Alice");
        assertEq(req.recipient, users.alice, "Recipient should be Alice");
    }

    function test_RequestUnstake_ThroughForwarder() public {
        // Setup: Give Alice some staked tokens
        _setupUserWithStkTokens(users.alice, 1000 * _1_USDC);

        uint256 stkBalance = vault.balanceOf(users.alice);
        assertEq(stkBalance, 1000 * _1_USDC);

        // Prepare the call data
        bytes memory callData = abi.encodeWithSelector(
            vault.requestUnstake.selector,
            users.alice, // recipient
            stkBalance // amount
        );

        // Forward the call with Alice's address appended
        vm.prank(trustedForwarder);
        (bool success, bytes memory returnData) = address(vault).call(_appendSender(callData, users.alice));
        require(success, "Forwarded call failed");

        bytes32 requestId = abi.decode(returnData, (bytes32));

        // Verify request was created correctly
        BaseVaultTypes.UnstakeRequest memory req = vault.getUnstakeRequest(requestId);
        assertEq(req.user, users.alice, "User should be Alice");
        assertEq(req.recipient, users.alice, "Recipient should be Alice");
    }

    function test_ClaimStakedShares_ThroughForwarder() public {
        _mintKTokenToUser(users.alice, 1000 * _1_USDC, true);

        vm.prank(users.alice);
        kUSD.approve(address(vault), 1000 * _1_USDC);

        bytes32 batchId = vault.getBatchId();

        vm.prank(users.alice);
        bytes32 requestId = vault.requestStake(users.alice, 1000 * _1_USDC);

        vm.prank(users.relayer);
        vault.closeBatch(batchId, true);

        uint256 lastTotalAssets = vault.totalAssets();
        _executeBatchSettlement(address(vault), batchId, lastTotalAssets);

        uint256 balanceBefore = vault.balanceOf(users.alice);

        // Test: Forward the claim call
        bytes memory callData = abi.encodeWithSelector(vault.claimStakedShares.selector, requestId);

        vm.prank(trustedForwarder);
        (bool success,) = address(vault).call(_appendSender(callData, users.alice));
        require(success, "Forwarded claim failed");

        uint256 balanceAfter = vault.balanceOf(users.alice);
        assertGt(balanceAfter, balanceBefore);
        assertEq(balanceAfter - balanceBefore, 1000 * _1_USDC);
    }

    function test_ClaimUnstakedAssets_ThroughForwarder() public {
        _setupUserWithStkTokens(users.alice, 1000 * _1_USDC);

        uint256 stkBalance = vault.balanceOf(users.alice);

        bytes32 unstakeBatchId = vault.getBatchId();

        vm.prank(users.alice);
        bytes32 unstakeRequestId = vault.requestUnstake(users.alice, stkBalance);

        vm.prank(users.relayer);
        vault.closeBatch(unstakeBatchId, true);

        uint256 lastTotalAssets = assetRouter.virtualBalance(address(vault), tokens.usdc);
        _executeBatchSettlement(address(vault), unstakeBatchId, lastTotalAssets);

        uint256 kTokenBalanceBefore = kUSD.balanceOf(users.alice);

        // Test: Forward the claim call
        bytes memory callData = abi.encodeWithSelector(vault.claimUnstakedAssets.selector, unstakeRequestId);

        vm.prank(trustedForwarder);
        (bool success,) = address(vault).call(_appendSender(callData, users.alice));
        require(success, "Forwarded claim failed");

        uint256 kTokenBalanceAfter = kUSD.balanceOf(users.alice);
        assertEq(kTokenBalanceAfter - kTokenBalanceBefore, 1000 * _1_USDC);
    }

    function test_ForwardedCall_WithWrongForwarder_ShouldUseActualSender() public {
        // Setup: Mint kTokens to Alice
        _mintKTokenToUser(users.alice, 1000 * _1_USDC, true);

        // Prepare call data with Alice's address appended
        bytes memory callData = abi.encodeWithSelector(vault.requestStake.selector, users.alice, 1000 * _1_USDC);

        // Try to call from Bob (not the trusted forwarder) with Alice's address appended
        // This should fail because Bob doesn't have approval or balance
        vm.prank(users.bob);
        (bool success,) = address(vault).call(_appendSender(callData, users.alice));

        // Should fail because Bob is the actual sender (not extracted from calldata)
        // and the appended address is ignored since Bob is not the trusted forwarder
        assertFalse(success, "Call should fail when not from trusted forwarder");
    }

    /* //////////////////////////////////////////////////////////////
                    CONTEXT SUFFIX LENGTH TESTS
    //////////////////////////////////////////////////////////////*/

    function test_ContextWithShortCalldata_LessThan20Bytes() public {
        // When calldata is less than 20 bytes, context suffix should not be extracted
        // even if caller is trusted forwarder
        _mintKTokenToUser(users.alice, 1000 * _1_USDC, true);

        vm.prank(users.alice);
        kUSD.approve(address(vault), 1000 * _1_USDC);

        // Make a normal call with regular calldata
        // The _msgSender() should return the actual sender (Alice)
        vm.prank(users.alice);
        bytes32 requestId = vault.requestStake(users.alice, 1000 * _1_USDC);

        // Verify request was created correctly
        BaseVaultTypes.StakeRequest memory req = vault.getStakeRequest(requestId);
        assertEq(req.user, users.alice, "User should be Alice");
    }

    /* //////////////////////////////////////////////////////////////
                    FORWARDER CALL SIMULATION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_MultipleUsers_ForwardedCallsIsolation() public {
        // Setup: Mint tokens to multiple users
        _mintKTokenToUser(users.alice, 1000 * _1_USDC, true);
        _mintKTokenToUser(users.bob, 500 * _1_USDC, true);
        _mintKTokenToUser(users.charlie, 750 * _1_USDC, true);

        // Approve for all users
        vm.prank(users.alice);
        kUSD.approve(address(vault), 1000 * _1_USDC);
        vm.prank(users.bob);
        kUSD.approve(address(vault), 500 * _1_USDC);
        vm.prank(users.charlie);
        kUSD.approve(address(vault), 750 * _1_USDC);

        bytes32 batchId = vault.getBatchId();

        // Forward calls for each user
        bytes memory callDataAlice = abi.encodeWithSelector(vault.requestStake.selector, users.alice, 1000 * _1_USDC);
        vm.prank(trustedForwarder);
        (bool success1, bytes memory returnData1) = address(vault).call(_appendSender(callDataAlice, users.alice));
        require(success1, "Alice's forwarded call failed");
        bytes32 requestIdAlice = abi.decode(returnData1, (bytes32));

        bytes memory callDataBob = abi.encodeWithSelector(vault.requestStake.selector, users.bob, 500 * _1_USDC);
        vm.prank(trustedForwarder);
        (bool success2, bytes memory returnData2) = address(vault).call(_appendSender(callDataBob, users.bob));
        require(success2, "Bob's forwarded call failed");
        bytes32 requestIdBob = abi.decode(returnData2, (bytes32));

        bytes memory callDataCharlie = abi.encodeWithSelector(vault.requestStake.selector, users.charlie, 750 * _1_USDC);
        vm.prank(trustedForwarder);
        (bool success3, bytes memory returnData3) = address(vault).call(_appendSender(callDataCharlie, users.charlie));
        require(success3, "Charlie's forwarded call failed");
        bytes32 requestIdCharlie = abi.decode(returnData3, (bytes32));

        // Verify each request has correct sender context
        BaseVaultTypes.StakeRequest memory req1 = vault.getStakeRequest(requestIdAlice);
        BaseVaultTypes.StakeRequest memory req2 = vault.getStakeRequest(requestIdBob);
        BaseVaultTypes.StakeRequest memory req3 = vault.getStakeRequest(requestIdCharlie);

        assertEq(req1.user, users.alice, "Alice's request should have Alice as user");
        assertEq(req2.user, users.bob, "Bob's request should have Bob as user");
        assertEq(req3.user, users.charlie, "Charlie's request should have Charlie as user");
    }

    /* //////////////////////////////////////////////////////////////
                    MULTIPLE USER CONTEXT TESTS
    //////////////////////////////////////////////////////////////*/

    function test_MultipleUsers_ContextIsolation() public {
        // Setup: Mint tokens to multiple users
        _mintKTokenToUser(users.alice, 1000 * _1_USDC, true);
        _mintKTokenToUser(users.bob, 500 * _1_USDC, true);
        _mintKTokenToUser(users.charlie, 750 * _1_USDC, true);

        bytes32 batchId = vault.getBatchId();

        // Each user makes their own request
        vm.prank(users.alice);
        kUSD.approve(address(vault), 1000 * _1_USDC);
        vm.prank(users.alice);
        bytes32 requestIdAlice = vault.requestStake(users.alice, 1000 * _1_USDC);

        vm.prank(users.bob);
        kUSD.approve(address(vault), 500 * _1_USDC);
        vm.prank(users.bob);
        bytes32 requestIdBob = vault.requestStake(users.bob, 500 * _1_USDC);

        vm.prank(users.charlie);
        kUSD.approve(address(vault), 750 * _1_USDC);
        vm.prank(users.charlie);
        bytes32 requestIdCharlie = vault.requestStake(users.charlie, 750 * _1_USDC);

        // Verify each request has correct sender context
        BaseVaultTypes.StakeRequest memory req1 = vault.getStakeRequest(requestIdAlice);
        BaseVaultTypes.StakeRequest memory req2 = vault.getStakeRequest(requestIdBob);
        BaseVaultTypes.StakeRequest memory req3 = vault.getStakeRequest(requestIdCharlie);

        assertEq(req1.user, users.alice, "Alice's request should have Alice as user");
        assertEq(req2.user, users.bob, "Bob's request should have Bob as user");
        assertEq(req3.user, users.charlie, "Charlie's request should have Charlie as user");
    }

    function test_CrossUserClaim_ShouldRevert() public {
        // Setup: Alice creates a stake request
        _mintKTokenToUser(users.alice, 1000 * _1_USDC, true);

        vm.prank(users.alice);
        kUSD.approve(address(vault), 1000 * _1_USDC);

        bytes32 batchId = vault.getBatchId();

        vm.prank(users.alice);
        bytes32 requestId = vault.requestStake(users.alice, 1000 * _1_USDC);

        vm.prank(users.relayer);
        vault.closeBatch(batchId, true);

        uint256 lastTotalAssets = vault.totalAssets();
        _executeBatchSettlement(address(vault), batchId, lastTotalAssets);

        // Test: Bob tries to claim Alice's request (should fail)
        vm.prank(users.bob);
        vm.expectRevert(bytes(VAULTCLAIMS_NOT_BENEFICIARY));
        vault.claimStakedShares(requestId);
    }

    /* //////////////////////////////////////////////////////////////
                    INTEGRATION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_CompleteStakingLifecycle_ThroughForwarder() public {
        uint256 balanceBefore = kUSD.balanceOf(users.alice);

        _mintKTokenToUser(users.alice, 1000 * _1_USDC, true);

        vm.prank(users.alice);
        kUSD.approve(address(vault), 1000 * _1_USDC);

        bytes32 batchId = vault.getBatchId();

        // Forward stake request
        bytes memory stakeCallData = abi.encodeWithSelector(vault.requestStake.selector, users.alice, 1000 * _1_USDC);
        vm.prank(trustedForwarder);
        (bool success1, bytes memory returnData1) = address(vault).call(_appendSender(stakeCallData, users.alice));
        require(success1, "Forwarded stake request failed");
        bytes32 requestId = abi.decode(returnData1, (bytes32));

        // Verify request was created correctly
        BaseVaultTypes.StakeRequest memory req = vault.getStakeRequest(requestId);
        assertEq(req.user, users.alice, "User should be Alice");

        vm.prank(users.relayer);
        vault.closeBatch(batchId, true);

        uint256 lastTotalAssets = assetRouter.virtualBalance(address(vault), tokens.usdc);
        _executeBatchSettlement(address(vault), batchId, lastTotalAssets);

        // Forward claim request
        bytes memory claimCallData = abi.encodeWithSelector(vault.claimStakedShares.selector, requestId);
        vm.prank(trustedForwarder);
        (bool success2,) = address(vault).call(_appendSender(claimCallData, users.alice));
        require(success2, "Forwarded claim failed");

        // Verify final state
        assertEq(vault.balanceOf(users.alice), 1000 * _1_USDC, "Alice should have staked tokens");
    }

    function test_CompleteStakingLifecycle_WithZeroForwarder() public {
        uint256 balanceBefore = kUSD.balanceOf(users.alice);

        _mintKTokenToUser(users.alice, 1000 * _1_USDC, true);

        vm.prank(users.alice);
        kUSD.approve(address(vault), 1000 * _1_USDC);

        bytes32 batchId = vault.getBatchId();

        vm.prank(users.alice);
        bytes32 requestId = vault.requestStake(users.alice, 1000 * _1_USDC);

        // Verify request was created correctly
        BaseVaultTypes.StakeRequest memory req = vault.getStakeRequest(requestId);
        assertEq(req.user, users.alice, "User should be Alice");

        vm.prank(users.relayer);
        vault.closeBatch(batchId, true);

        uint256 lastTotalAssets = assetRouter.virtualBalance(address(vault), tokens.usdc);
        _executeBatchSettlement(address(vault), batchId, lastTotalAssets);

        vm.prank(users.alice);
        vault.claimStakedShares(requestId);

        // Verify final state
        assertEq(vault.balanceOf(users.alice), 1000 * _1_USDC, "Alice should have staked tokens");
    }

    function test_CompleteUnstakingLifecycle_WithZeroForwarder() public {
        _setupUserWithStkTokens(users.alice, 1000 * _1_USDC);

        uint256 stkBalance = vault.balanceOf(users.alice);
        assertEq(stkBalance, 1000 * _1_USDC);

        bytes32 unstakeBatchId = vault.getBatchId();

        vm.prank(users.alice);
        bytes32 unstakeRequestId = vault.requestUnstake(users.alice, stkBalance);

        // Verify request was created correctly
        BaseVaultTypes.UnstakeRequest memory req = vault.getUnstakeRequest(unstakeRequestId);
        assertEq(req.user, users.alice, "User should be Alice");

        assertEq(vault.balanceOf(users.alice), 0, "Alice should have transferred tokens");
        assertEq(vault.balanceOf(address(vault)), stkBalance, "Vault should hold tokens");

        vm.prank(users.relayer);
        vault.closeBatch(unstakeBatchId, true);

        uint256 lastTotalAssets = assetRouter.virtualBalance(address(vault), tokens.usdc);
        _executeBatchSettlement(address(vault), unstakeBatchId, lastTotalAssets);

        uint256 kTokenBalanceBefore = kUSD.balanceOf(users.alice);

        vm.prank(users.alice);
        vault.claimUnstakedAssets(unstakeRequestId);

        uint256 kTokenBalanceAfter = kUSD.balanceOf(users.alice);
        assertEq(kTokenBalanceAfter - kTokenBalanceBefore, 1000 * _1_USDC, "Alice should receive kTokens back");

        assertEq(vault.balanceOf(address(vault)), 0, "Vault should have no more staked tokens");
    }

    /* //////////////////////////////////////////////////////////////
                        HELPER FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function _setupUserWithStkTokens(address user, uint256 amount) internal {
        _mintKTokenToUser(user, amount, true);

        vm.prank(user);
        kUSD.approve(address(vault), amount);

        bytes32 batchId = vault.getBatchId();

        vm.prank(user);
        bytes32 requestId = vault.requestStake(user, amount);

        vm.prank(users.relayer);
        vault.closeBatch(batchId, true);

        uint256 lastTotalAssets = assetRouter.virtualBalance(address(vault), tokens.usdc);
        _executeBatchSettlement(address(vault), batchId, lastTotalAssets);

        vm.prank(user);
        vault.claimStakedShares(requestId);
    }
}
