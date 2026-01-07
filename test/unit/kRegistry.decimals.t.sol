// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { Test } from "forge-std/Test.sol";
import { kRegistry } from "kam/src/kRegistry/kRegistry.sol";

/// @notice Harness contract to expose internal _tryGetAssetDecimals for testing
contract kRegistryHarness is kRegistry {
    function tryGetAssetDecimals(address _underlying) external view returns (bool _success, uint8 _result) {
        return _tryGetAssetDecimals(_underlying);
    }
}

/// @notice Simple mock token for testing decimals
contract MockDecimalsToken {
    uint8 private immutable _decimals;

    constructor(uint8 decimals_) {
        _decimals = decimals_;
    }

    function decimals() external view returns (uint8) {
        return _decimals;
    }
}

/// @notice Mock token without decimals() function
contract TokenWithoutDecimals {
    string public name = "No Decimals";
    string public symbol = "ND";
}

/// @notice Mock contract that returns oversized value (>= 256, invalid for uint8)
contract OversizedDecimalsToken {
    function decimals() external pure returns (bytes32) {
        return bytes32(uint256(300));
    }
}

/// @notice Mock contract that returns value >= 256 (invalid for uint8)
contract InvalidDecimalsToken {
    function decimals() external pure returns (uint256) {
        return 256;
    }
}

/// @notice Mock contract that reverts on decimals()
contract RevertingDecimalsToken {
    function decimals() external pure {
        revert("No decimals");
    }
}

/// @notice Mock contract that returns empty data
contract EmptyReturnToken {
    fallback() external { }
}

contract kRegistryDecimalsTest is Test {
    kRegistryHarness internal harness;

    function setUp() public {
        harness = new kRegistryHarness();
    }

    function test_TryGetAssetDecimals_StandardToken_18Decimals() public {
        address token = _deployMockToken(18);

        (bool success, uint8 decimals) = harness.tryGetAssetDecimals(token);

        assertTrue(success);
        assertEq(decimals, 18);
    }

    function test_TryGetAssetDecimals_USDC_6Decimals() public {
        address token = _deployMockToken(6);

        (bool success, uint8 decimals) = harness.tryGetAssetDecimals(token);

        assertTrue(success);
        assertEq(decimals, 6);
    }

    function test_TryGetAssetDecimals_WBTC_8Decimals() public {
        address token = _deployMockToken(8);

        (bool success, uint8 decimals) = harness.tryGetAssetDecimals(token);

        assertTrue(success);
        assertEq(decimals, 8);
    }

    function test_TryGetAssetDecimals_ZeroDecimals() public {
        address token = _deployMockToken(0);

        (bool success, uint8 decimals) = harness.tryGetAssetDecimals(token);

        assertTrue(success);
        assertEq(decimals, 0);
    }

    function test_TryGetAssetDecimals_MaxValidDecimals() public {
        address token = _deployMockToken(255);

        (bool success, uint8 decimals) = harness.tryGetAssetDecimals(token);

        assertTrue(success);
        assertEq(decimals, 255);
    }

    function test_TryGetAssetDecimals_ZeroAddress_ReturnsFalse() public view {
        (bool success, uint8 decimals) = harness.tryGetAssetDecimals(address(0));

        assertFalse(success);
        assertEq(decimals, 0);
    }

    function test_TryGetAssetDecimals_EOA_ReturnsFalse() public {
        address eoa = makeAddr("EOA");

        (bool success, uint8 decimals) = harness.tryGetAssetDecimals(eoa);

        assertFalse(success);
        assertEq(decimals, 0);
    }

    function test_TryGetAssetDecimals_TokenWithoutDecimals_ReturnsFalse() public {
        TokenWithoutDecimals token = new TokenWithoutDecimals();

        (bool success, uint8 decimals) = harness.tryGetAssetDecimals(address(token));

        assertFalse(success);
        assertEq(decimals, 0);
    }

    function test_TryGetAssetDecimals_OversizedResponse_ReturnsFalse() public {
        OversizedDecimalsToken token = new OversizedDecimalsToken();

        (bool success, uint8 decimals) = harness.tryGetAssetDecimals(address(token));

        assertFalse(success);
        assertEq(decimals, 0);
    }

    function test_TryGetAssetDecimals_InvalidDecimals_ReturnsFalse() public {
        InvalidDecimalsToken token = new InvalidDecimalsToken();

        (bool success, uint8 decimals) = harness.tryGetAssetDecimals(address(token));

        assertFalse(success);
        assertEq(decimals, 0);
    }

    function test_TryGetAssetDecimals_RevertingToken_ReturnsFalse() public {
        RevertingDecimalsToken token = new RevertingDecimalsToken();

        (bool success, uint8 decimals) = harness.tryGetAssetDecimals(address(token));

        assertFalse(success);
        assertEq(decimals, 0);
    }

    function test_TryGetAssetDecimals_EmptyReturn_ReturnsFalse() public {
        EmptyReturnToken token = new EmptyReturnToken();

        (bool success, uint8 decimals) = harness.tryGetAssetDecimals(address(token));

        assertFalse(success);
        assertEq(decimals, 0);
    }

    function testFuzz_TryGetAssetDecimals_ValidDecimals(uint8 _decimals) public {
        address token = _deployMockToken(_decimals);

        (bool success, uint8 decimals) = harness.tryGetAssetDecimals(token);

        assertTrue(success);
        assertEq(decimals, _decimals);
    }

    function _deployMockToken(uint8 _decimals) internal returns (address) {
        return address(new MockDecimalsToken(_decimals));
    }
}
