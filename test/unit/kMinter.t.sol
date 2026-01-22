// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { MockERC20 } from "../mocks/MockERC20.sol";
import { _1_USDC } from "../utils/Constants.sol";
import { DeploymentBaseTest } from "../utils/DeploymentBaseTest.sol";

import { Initializable } from "solady/utils/Initializable.sol";
import { MinimalProxyFactory } from "src/vendor/solady/utils/MinimalProxyFactory.sol";

import { IkToken } from "kToken0/interfaces/IkToken.sol";
import { kBase } from "kam/src/base/kBase.sol";
import {
    KBASE_WRONG_ASSET,
    KBASE_WRONG_ROLE,
    KBASE_ZERO_ADDRESS,
    KBASE_ZERO_AMOUNT,
    KMINTER_BATCH_MINT_REACHED,
    KMINTER_BATCH_NOT_SETTLED,
    KMINTER_BATCH_REDEEM_REACHED,
    KMINTER_IS_PAUSED,
    KMINTER_REQUEST_NOT_FOUND,
    KMINTER_UNAUTHORIZED,
    KMINTER_WRONG_ROLE,
    KMINTER_ZERO_ADDRESS,
    KMINTER_ZERO_AMOUNT,
    KREGISTRY_ZERO_ADDRESS
} from "kam/src/errors/Errors.sol";
import { IkMinter } from "kam/src/interfaces/IkMinter.sol";
import { kMinter } from "kam/src/kMinter.sol";
import { Ownable } from "solady/auth/Ownable.sol";

contract kMinterTest is DeploymentBaseTest {
    uint256 internal constant MINT_AMOUNT = 100_000 * _1_USDC;
    uint256 internal constant REQUEST_AMOUNT = 50_000 * _1_USDC;
    uint256 internal constant _1_DAI = 1e18;
    address internal constant ZERO_ADDRESS = address(0);
    address USDC;
    address WBTC;
    address DAI;
    address _minter;

    MockERC20 public mockDAI;

    function setUp() public override {
        DeploymentBaseTest.setUp();

        USDC = address(mockUSDC);
        WBTC = address(mockWBTC);
        _minter = address(minter);

        // Deploy mockDAI for rescue assets test (not a protocol asset)
        mockDAI = new MockERC20("Mock DAI", "DAI", 18);
        DAI = address(mockDAI);
        vm.label(DAI, "DAI");
    }

    /* //////////////////////////////////////////////////////////////
                        INITIALIZATION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Initialize_Success() public view {
        assertEq(minter.contractName(), "kMinter");
        assertEq(minter.contractVersion(), "1.0.0");
        assertFalse(minter.isPaused());
        assertEq(address(minter.registry()), address(registry));
        assertEq(minter.getRequestCounter(), 0);
    }

    function test_Initialize_Require_Registry_Not_Zero_Address() public {
        kMinter newMinterImpl = new kMinter();

        bytes memory initData = abi.encodeCall(kMinter.initialize, (address(0), users.admin));

        MinimalProxyFactory factory = new MinimalProxyFactory();

        vm.expectRevert(bytes(KMINTER_ZERO_ADDRESS));
        factory.deployAndCall(address(newMinterImpl), initData);
    }

    function test_Initialize_Require_Owner_Not_Zero_Address() public {
        kMinter newMinterImpl = new kMinter();

        bytes memory initData = abi.encodeCall(kMinter.initialize, (address(registry), ZERO_ADDRESS));

        MinimalProxyFactory factory = new MinimalProxyFactory();

        vm.expectRevert(bytes(KMINTER_ZERO_ADDRESS));
        factory.deployAndCall(address(newMinterImpl), initData);
    }

    function test_Initialize_Require_Not_Initialized() public {
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        minter.initialize(address(registry), users.owner);
    }

    /* //////////////////////////////////////////////////////////////
                                MINT
    //////////////////////////////////////////////////////////////*/

    function test_Mint_Success() public {
        bytes32 _batchId = minter.getBatchId(USDC);
        uint256 _balanceBefore = kUSD.balanceOf(users.institution);
        mockUSDC.mint(users.institution, MINT_AMOUNT);

        vm.prank(users.institution);
        mockUSDC.approve(_minter, MINT_AMOUNT);

        vm.prank(users.institution);
        vm.expectEmit(true, true, true, true);
        emit IkMinter.Minted(users.institution, MINT_AMOUNT, _batchId);
        minter.mint(USDC, users.institution, MINT_AMOUNT);
        assertEq(kUSD.balanceOf(users.institution), _balanceBefore + MINT_AMOUNT);

        assertEq(minter.getTotalLockedAssets(USDC), MINT_AMOUNT);

        (uint256 _deposit,) = assetRouter.getBatchIdBalances(_minter, _batchId);
        assertEq(_deposit, MINT_AMOUNT);

        assertEq(mockUSDC.balanceOf(address(minterAdapterUSDC)), MINT_AMOUNT);
    }

    function test_Mint_Require_Not_Paused() public {
        bool _paused = true;
        vm.prank(users.emergencyAdmin);
        vm.expectEmit(true, false, false, true);
        emit kBase.Paused(_paused);
        minter.setPaused(_paused);

        vm.prank(users.institution);
        vm.expectRevert(bytes(KMINTER_IS_PAUSED));
        minter.mint(USDC, users.institution, MINT_AMOUNT);
    }

    function test_Mint_Require_Only_Institution() public {
        vm.prank(users.alice);
        vm.expectRevert(bytes(KMINTER_WRONG_ROLE));
        minter.mint(USDC, users.alice, MINT_AMOUNT);

        vm.prank(users.admin);
        vm.expectRevert(bytes(KMINTER_WRONG_ROLE));
        minter.mint(USDC, users.admin, MINT_AMOUNT);
    }

    function test_Mint_Require_Valid_Asset() public {
        address invalidAsset = address(0x347474);

        vm.prank(users.institution);
        vm.expectRevert(bytes(KREGISTRY_ZERO_ADDRESS));
        minter.mint(invalidAsset, users.institution, MINT_AMOUNT);
    }

    function test_Mint_Require_Amount_Not_Zero() public {
        vm.prank(users.institution);
        vm.expectRevert(bytes(KMINTER_ZERO_AMOUNT));
        minter.mint(USDC, users.institution, 0);
    }

    function test_Mint_Require_To_Address_Not_Zero() public {
        vm.prank(users.institution);
        vm.expectRevert(bytes(KMINTER_ZERO_ADDRESS));
        minter.mint(USDC, ZERO_ADDRESS, MINT_AMOUNT);
    }

    function test_Mint_Require_Amount_Below_Batch_Max_Mint() public {
        vm.prank(users.admin);
        registry.setBatchLimits(USDC, MINT_AMOUNT - 1, MINT_AMOUNT);

        vm.prank(users.institution);
        vm.expectRevert(bytes(KMINTER_BATCH_MINT_REACHED));
        minter.mint(USDC, users.alice, MINT_AMOUNT);
    }

    /* //////////////////////////////////////////////////////////////
                            REQUEST BURN
    //////////////////////////////////////////////////////////////*/

    function test_RequestBurn_Success() public {
        _mint(USDC, users.institution, MINT_AMOUNT);
        bytes32 _batchId = minter.getBatchId(USDC);

        vm.prank(users.institution);
        kUSD.approve(_minter, MINT_AMOUNT);

        assertEq(minter.isPaused(), false);

        vm.prank(users.institution);
        vm.expectEmit(false, true, false, false);
        emit IkMinter.BurnRequestCreated(bytes32(0), users.institution, address(kUSD), REQUEST_AMOUNT, _batchId);
        bytes32 _requestId = minter.requestBurn(USDC, users.institution, REQUEST_AMOUNT);
        assertEq(minter.getBurnRequest(_requestId).user, users.institution);
        assertEq(minter.getBurnRequest(_requestId).asset, USDC);
        assertEq(minter.getBurnRequest(_requestId).amount, REQUEST_AMOUNT);

        assertEq(minter.getTotalLockedAssets(USDC), MINT_AMOUNT); // Only changes on Burn.

        (, uint256 _requested) = assetRouter.getBatchIdBalances(_minter, _batchId);
        assertEq(_requested, REQUEST_AMOUNT);

        assertEq(kUSD.balanceOf(_minter), REQUEST_AMOUNT);

        assertEq(minter.getRequestCounter(), 1);

        // Verify batch receiver was created during requestBurn
        address _batchReceiver = minter.getBatchReceiver(_batchId);
        assertTrue(_batchReceiver != address(0));
    }

    function test_RequestBurn_Require_Not_Paused() public {
        bool _paused = true;
        vm.prank(users.emergencyAdmin);
        minter.setPaused(_paused);

        vm.prank(users.institution);
        vm.expectRevert(bytes(KMINTER_IS_PAUSED));
        minter.requestBurn(USDC, users.institution, REQUEST_AMOUNT);
    }

    function test_RequestBurn_Require_Only_Institution() public {
        vm.prank(users.alice);
        vm.expectRevert(bytes(KMINTER_WRONG_ROLE));
        minter.requestBurn(USDC, users.alice, REQUEST_AMOUNT);

        vm.prank(users.admin);
        vm.expectRevert(bytes(KMINTER_WRONG_ROLE));
        minter.requestBurn(USDC, users.admin, REQUEST_AMOUNT);
    }

    function test_RequestBurn_Require_Valid_Asset() public {
        address invalidAsset = address(0x347474);

        vm.prank(users.institution);
        vm.expectRevert(bytes(KREGISTRY_ZERO_ADDRESS));
        minter.requestBurn(invalidAsset, users.institution, REQUEST_AMOUNT);
    }

    function test_RequestBurn_Require_Amount_Not_Zero() public {
        vm.prank(users.institution);
        vm.expectRevert(bytes(KMINTER_ZERO_AMOUNT));
        minter.requestBurn(USDC, users.institution, 0);
    }

    function test_RequestBurn_Require_To_Address_Not_Zero() public {
        vm.prank(users.institution);
        vm.expectRevert(bytes(KMINTER_ZERO_ADDRESS));
        minter.requestBurn(USDC, ZERO_ADDRESS, REQUEST_AMOUNT);
    }

    function test_RequestBurn_Require_Amount_Below_Batch_Max_Redeem() public {
        _mint(USDC, users.institution, MINT_AMOUNT);

        vm.prank(users.admin);
        registry.setBatchLimits(USDC, MINT_AMOUNT, REQUEST_AMOUNT - 1);

        vm.prank(users.institution);
        vm.expectRevert(bytes(KMINTER_BATCH_REDEEM_REACHED));
        minter.requestBurn(USDC, users.institution, REQUEST_AMOUNT);
    }

    /* //////////////////////////////////////////////////////////////
                            BURN
    //////////////////////////////////////////////////////////////*/

    function test_Burn_Success() public {
        _mint(USDC, users.institution, MINT_AMOUNT);
        uint256 _aBalanceAfterMint = mockUSDC.balanceOf(users.institution);
        _requestBurn(USDC, users.institution, REQUEST_AMOUNT);

        bytes32[] memory _requestIds = minter.getUserRequests(users.institution);
        vm.prank(users.institution);
        vm.expectEmit(false, false, true, false);
        emit IkMinter.Burned(bytes32(0), address(0), address(kUSD), users.institution, REQUEST_AMOUNT, bytes32(0));
        minter.burn(_requestIds[0]);

        assertEq(kUSD.balanceOf(users.institution), REQUEST_AMOUNT); // TEST_AMOUNT = 2x REQUEST_AMOUNT, 1 was withdrawn
        assertEq(mockUSDC.balanceOf(users.institution), _aBalanceAfterMint + REQUEST_AMOUNT);

        assertEq(minter.getTotalLockedAssets(USDC), REQUEST_AMOUNT); // half burned

        assertEq(mockUSDC.balanceOf(_minter), 0);
    }

    function test_Burn_Require_Not_Paused() public {
        _mint(USDC, users.institution, MINT_AMOUNT);
        _requestBurn(USDC, users.institution, REQUEST_AMOUNT);

        vm.prank(users.emergencyAdmin);
        minter.setPaused(true);

        bytes32[] memory _requestIds = minter.getUserRequests(users.institution);
        vm.prank(users.institution);
        vm.expectRevert(bytes(KMINTER_IS_PAUSED));
        minter.burn(_requestIds[0]);
    }

    function test_Burn_Require_Only_Institution() public {
        _mint(USDC, users.institution, MINT_AMOUNT);
        _requestBurn(USDC, users.institution, REQUEST_AMOUNT);

        bytes32[] memory _requestIds = minter.getUserRequests(users.institution);
        vm.prank(users.alice);
        vm.expectRevert(bytes(KMINTER_WRONG_ROLE));
        minter.burn(_requestIds[0]);

        vm.prank(users.admin);
        vm.expectRevert(bytes(KMINTER_WRONG_ROLE));
        minter.burn(_requestIds[0]);

        // Different institution cannot burn another institution's request
        vm.prank(users.institution2);
        vm.expectRevert(bytes(KMINTER_UNAUTHORIZED));
        minter.burn(_requestIds[0]);
    }

    function test_Burn_Require_Valid_RequestId() public {
        bytes32 invalidRequestId = keccak256("Banana");

        // Invalid request ID will have user = address(0), so authorization check fails first
        vm.prank(users.institution);
        vm.expectRevert(bytes(KMINTER_UNAUTHORIZED));
        minter.burn(invalidRequestId);
    }

    function test_Burn_Require_Status_Pending() public {
        _mint(USDC, users.institution, MINT_AMOUNT);
        _requestBurn(USDC, users.institution, REQUEST_AMOUNT);

        bytes32[] memory _requestIds = minter.getUserRequests(users.institution);
        vm.prank(users.institution);
        minter.burn(_requestIds[0]);

        vm.prank(users.institution);
        vm.expectRevert(bytes(KMINTER_REQUEST_NOT_FOUND));
        minter.burn(_requestIds[0]);
    }

    function test_Burn_Require_BatchId_Settled() public {
        _mint(USDC, users.institution, MINT_AMOUNT);

        address _kToken = registry.assetToKToken(USDC);
        vm.prank(users.institution);
        IkToken(_kToken).approve(_minter, REQUEST_AMOUNT);

        vm.prank(users.institution);
        bytes32 _requestId = minter.requestBurn(USDC, users.institution, REQUEST_AMOUNT);

        bytes32 _batchId = minter.getBatchId(USDC);
        address _batchReceiver = minter.getBatchReceiver(_batchId);
        mockUSDC.mint(_batchReceiver, REQUEST_AMOUNT);

        vm.prank(users.institution);
        vm.expectRevert(bytes(KMINTER_BATCH_NOT_SETTLED));
        minter.burn(_requestId);
    }

    /* //////////////////////////////////////////////////////////////
                        UPGRADE TESTS
    //////////////////////////////////////////////////////////////*/

    /// @dev ERC-1967 implementation slot
    bytes32 internal constant IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    function test_AuthorizeUpgrade_Sucess() public {
        address oldImpl = address(uint160(uint256(vm.load(address(minter), IMPLEMENTATION_SLOT))));
        address newImpl = address(new kMinter());

        assertFalse(oldImpl == newImpl);

        vm.prank(users.admin);
        minter.upgradeToAndCall(newImpl, "");

        address currentImpl = address(uint160(uint256(vm.load(address(minter), IMPLEMENTATION_SLOT))));
        assertEq(currentImpl, newImpl);
        assertFalse(currentImpl == oldImpl);
    }

    function test_AuthorizeUpgrade_Require_Only_Admin() public {
        address newImpl = address(new kMinter());

        vm.prank(users.alice);
        vm.expectRevert(Ownable.Unauthorized.selector);
        minter.upgradeToAndCall(newImpl, "");
    }

    function test_AuthorizeUpgrade_Require_Implementation_Not_Zero_Address() public {
        vm.prank(users.admin);
        vm.expectRevert(bytes(KMINTER_ZERO_ADDRESS));
        minter.upgradeToAndCall(ZERO_ADDRESS, "");
    }

    /* //////////////////////////////////////////////////////////////
                        RESCUE ASSETS TESTS - ERC20
    //////////////////////////////////////////////////////////////*/

    function test_RescueAssets_ERC20_Success() public {
        uint256 _amount = 10 * _1_DAI;
        mockDAI.mint(_minter, _amount);

        uint256 _balanceBefore = mockDAI.balanceOf(users.treasury);
        assertEq(mockDAI.balanceOf(_minter), _amount);

        vm.prank(users.admin);
        vm.expectEmit(true, true, false, true);
        emit kBase.RescuedAssets(DAI, users.treasury, _amount);
        minter.rescueAssets(DAI, users.treasury, _amount);

        assertEq(mockDAI.balanceOf(users.treasury), _balanceBefore + _amount);
        assertEq(mockDAI.balanceOf(_minter), 0);
    }

    function test_RescueAssets_Require_Only_Admin() public {
        uint256 _amount = 5 * _1_DAI;
        mockDAI.mint(_minter, _amount);

        vm.prank(users.alice);
        vm.expectRevert(bytes(KBASE_WRONG_ROLE));
        minter.rescueAssets(DAI, users.treasury, _amount);

        vm.prank(users.emergencyAdmin);
        vm.expectRevert(bytes(KBASE_WRONG_ROLE));
        minter.rescueAssets(DAI, users.treasury, _amount);

        vm.prank(users.institution);
        vm.expectRevert(bytes(KBASE_WRONG_ROLE));
        minter.rescueAssets(DAI, users.treasury, _amount);

        assertEq(mockDAI.balanceOf(_minter), _amount);
    }

    function test_RescueAssets_Require_To_Address_Not_Zero() public {
        uint256 _amount = 5 * _1_DAI;
        mockDAI.mint(_minter, _amount);

        vm.prank(users.admin);
        vm.expectRevert(bytes(KBASE_ZERO_ADDRESS));
        minter.rescueAssets(DAI, ZERO_ADDRESS, _amount);

        assertEq(mockDAI.balanceOf(_minter), _amount);
    }

    function test_RescueAssets_Require_Amount_Not_Zero() public {
        uint256 _amount = 5 * _1_DAI;
        mockDAI.mint(_minter, _amount);

        vm.prank(users.admin);
        vm.expectRevert(bytes(KBASE_ZERO_AMOUNT));
        minter.rescueAssets(DAI, users.treasury, 0);

        assertEq(mockDAI.balanceOf(_minter), _amount);
    }

    function test_RescueAssets_Require_Amount_Below_Balance() public {
        uint256 _mintAmount = 5 * _1_DAI;
        uint256 _rescueAmount = 10 * _1_DAI;
        mockDAI.mint(_minter, _mintAmount);

        vm.prank(users.admin);
        vm.expectRevert(bytes(KBASE_ZERO_AMOUNT));
        minter.rescueAssets(DAI, users.treasury, _rescueAmount);

        assertEq(mockDAI.balanceOf(_minter), _mintAmount);
    }

    function test_RescueAssets_Require_Not_Protocol_Asset() public {
        uint256 _amount = 1000 * _1_USDC;
        mockUSDC.mint(_minter, _amount);

        vm.prank(users.admin);
        vm.expectRevert(bytes(KBASE_WRONG_ASSET));
        minter.rescueAssets(USDC, users.treasury, _amount);

        assertEq(mockUSDC.balanceOf(_minter), _amount);
    }

    function test_RescueAssets_Require_Not_KToken() public {
        address _kToken = registry.assetToKToken(USDC);
        uint256 _amount = 1000 * _1_USDC;

        // Mint kTokens directly to kMinter (simulating escrowed tokens)
        vm.prank(_minter);
        IkToken(_kToken).mint(_minter, _amount);

        vm.prank(users.admin);
        vm.expectRevert(bytes(KBASE_WRONG_ASSET));
        minter.rescueAssets(_kToken, users.treasury, _amount);

        assertEq(IkToken(_kToken).balanceOf(_minter), _amount);
    }

    /* //////////////////////////////////////////////////////////////
                        RESCUE ASSETS TESTS - ETH
    //////////////////////////////////////////////////////////////*/

    function test_RescueAssets_ETH_Success() public {
        uint256 _amount = 1 ether;
        vm.deal(_minter, _amount);
        assertEq(_minter.balance, _amount);

        uint256 _balanceBefore = users.treasury.balance;

        vm.prank(users.admin);
        vm.expectEmit(true, false, false, true);
        emit kBase.RescuedETH(users.treasury, _amount);
        minter.rescueAssets(ZERO_ADDRESS, users.treasury, _amount);

        assertEq(users.treasury.balance, _balanceBefore + _amount);
        assertEq(_minter.balance, 0);
    }

    function test_RescueAssets_ETH_Require_Only_Admin() public {
        uint256 _amount = 1 ether;
        vm.deal(_minter, _amount);

        vm.prank(users.alice);
        vm.expectRevert(bytes(KBASE_WRONG_ROLE));
        minter.rescueAssets(ZERO_ADDRESS, users.treasury, _amount);

        vm.prank(users.emergencyAdmin);
        vm.expectRevert(bytes(KBASE_WRONG_ROLE));
        minter.rescueAssets(ZERO_ADDRESS, users.treasury, _amount);

        vm.prank(users.institution);
        vm.expectRevert(bytes(KBASE_WRONG_ROLE));
        minter.rescueAssets(ZERO_ADDRESS, users.treasury, _amount);

        assertEq(_minter.balance, _amount);
    }

    function test_RescueAssets_ETH_Require_To_Address_Not_Zero() public {
        uint256 _amount = 1 ether;
        vm.deal(_minter, _amount);

        vm.prank(users.admin);
        vm.expectRevert(bytes(KBASE_ZERO_ADDRESS));
        minter.rescueAssets(ZERO_ADDRESS, ZERO_ADDRESS, _amount);

        assertEq(_minter.balance, _amount);
    }

    function test_RescueAssets_ETH_Require_Amount_Not_Zero() public {
        uint256 _amount = 1 ether;
        vm.deal(_minter, _amount);

        vm.prank(users.admin);
        vm.expectRevert(bytes(KBASE_ZERO_AMOUNT));
        minter.rescueAssets(ZERO_ADDRESS, users.treasury, 0);

        assertEq(_minter.balance, _amount);
    }

    function test_RescueAssets_ETH_Require_Amount_Below_Balance() public {
        uint256 _mintAmount = 1 ether;
        uint256 _rescueAmount = 2 ether;
        vm.deal(_minter, _mintAmount);

        vm.prank(users.admin);
        vm.expectRevert(bytes(KBASE_ZERO_AMOUNT));
        minter.rescueAssets(ZERO_ADDRESS, users.treasury, _rescueAmount);

        assertEq(_minter.balance, _mintAmount);
    }

    /* //////////////////////////////////////////////////////////////
                                INTERNAL
    //////////////////////////////////////////////////////////////*/

    // Since the protocol is async, in order for the requests to happen we will have to have the 1st deposits settled
    function _mint(address _asset, address _to, uint256 _amount) internal {
        mockUSDC.mint(users.institution, _amount);

        vm.prank(users.institution);
        mockUSDC.approve(_minter, _amount);

        vm.prank(users.institution);
        minter.mint(_asset, _to, _amount);

        bytes32 _batchId = minter.getBatchId(USDC);
        vm.prank(users.relayer);
        minter.closeBatch(_batchId, true);

        vm.prank(users.admin);
        assetRouter.setSettlementCooldown(0);

        vm.prank(users.relayer);
        bytes32 _proposalId = assetRouter.proposeSettleBatch(_asset, _minter, _batchId, 0, 0, 0);
        assetRouter.executeSettleBatch(_proposalId);
    }

    function _requestBurn(address _asset, address _to, uint256 _amount) internal {
        address _kToken = registry.assetToKToken(_asset);
        vm.prank(users.institution);
        IkToken(_kToken).approve(_minter, _amount);

        vm.prank(users.institution);
        minter.requestBurn(_asset, _to, _amount);

        bytes32 _batchId = minter.getBatchId(USDC);
        vm.prank(users.relayer);
        minter.closeBatch(_batchId, true);

        vm.prank(users.admin);
        assetRouter.setSettlementCooldown(0);

        uint256 _totalAssets = IkToken(_kToken).totalSupply();
        vm.prank(users.relayer);
        bytes32 _proposalId = assetRouter.proposeSettleBatch(_asset, _minter, _batchId, _totalAssets, 0, 0);
        assetRouter.executeSettleBatch(_proposalId);
    }
}
