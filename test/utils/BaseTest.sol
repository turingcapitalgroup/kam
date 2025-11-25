// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import { MockERC20 } from "../mocks/MockERC20.sol";
import { Utilities } from "./Utilities.sol";
import { stdJson } from "forge-std/StdJson.sol";
import { Test } from "forge-std/Test.sol";

contract BaseTest is Test {
    using stdJson for string;

    Utilities internal utils;

    // Test users
    struct Users {
        address payable alice;
        address payable bob;
        address payable charlie;
        address payable admin;
        address payable emergencyAdmin;
        address payable institution;
        address payable institution2;
        address payable institution3;
        address payable institution4;
        address payable relayer;
        address payable treasury;
        address payable owner;
        address payable guardian;
    }

    Users internal users;

    struct Tokens {
        address usdc;
        address wbtc;
    }

    Tokens internal tokens;

    // Mock tokens
    MockERC20 public mockUSDC;
    MockERC20 public mockWBTC;

    function setUp() public virtual {
        utils = new Utilities();

        // Set up test assets
        _setupAssets();

        // Create test users
        _createUsers();

        // Label addresses for better trace output
        _labelAddresses();
    }

    function getMockUSDC() internal view returns (MockERC20) {
        return mockUSDC;
    }

    function getMockWBTC() internal view returns (MockERC20) {
        return mockWBTC;
    }

    function _createUsers() internal {
        // Regular test users (random addresses)
        users.alice = utils.createUser("Alice");
        users.bob = utils.createUser("Bob");
        users.charlie = utils.createUser("Charlie");

        string memory configPath = "deployments/config/localhost.json";
        require(vm.exists(configPath), "Config file not found: deployments/config/localhost.json");

        string memory json = vm.readFile(configPath);

        users.owner = payable(json.readAddress(".roles.owner"));
        users.admin = payable(json.readAddress(".roles.admin"));
        users.emergencyAdmin = payable(json.readAddress(".roles.emergencyAdmin"));
        users.guardian = payable(json.readAddress(".roles.guardian"));
        users.relayer = payable(json.readAddress(".roles.relayer"));
        users.institution = payable(json.readAddress(".roles.institution"));
        users.treasury = payable(json.readAddress(".roles.treasury"));

        // Additional test institutions (random)
        users.institution2 = utils.createUser("Institution2");
        users.institution3 = utils.createUser("Institution3");
        users.institution4 = utils.createUser("Institution4");
    }

    /// @notice Setup assets from deployment script return values
    function _setupAssets(address usdcAddr, address wbtcAddr) internal {
        require(usdcAddr != address(0), "USDC address is zero");
        require(wbtcAddr != address(0), "WBTC address is zero");

        mockUSDC = MockERC20(usdcAddr);
        mockWBTC = MockERC20(wbtcAddr);
        tokens.usdc = usdcAddr;
        tokens.wbtc = wbtcAddr;

        vm.label(tokens.usdc, "USDC");
        vm.label(tokens.wbtc, "WBTC");
    }

    /// @notice Setup assets from JSON config (fallback for non-deployment tests)
    function _setupAssets() internal {
        string memory configPath = "deployments/config/localhost.json";
        require(vm.exists(configPath), "Config file not found: deployments/config/localhost.json");

        string memory json = vm.readFile(configPath);

        // Read deployed mock assets from config (scripts update this)
        require(json.keyExists(".assets.USDC"), "USDC address not found in config - run 00_DeployMockAssets.s.sol");
        require(json.keyExists(".assets.WBTC"), "WBTC address not found in config - run 00_DeployMockAssets.s.sol");

        address usdcAddr = json.readAddress(".assets.USDC");
        address wbtcAddr = json.readAddress(".assets.WBTC");

        _setupAssets(usdcAddr, wbtcAddr);
    }

    function _labelAddresses() internal {
        vm.label(users.alice, "Alice");
        vm.label(users.bob, "Bob");
        vm.label(users.charlie, "Charlie");
        vm.label(users.admin, "Admin");
        vm.label(users.emergencyAdmin, "EmergencyAdmin");
        vm.label(users.institution, "Institution");
        vm.label(users.relayer, "Relayer");
        vm.label(users.treasury, "Treasury");
        vm.label(users.owner, "Owner");
        vm.label(users.guardian, "Guardian");
        vm.label(users.institution2, "Institution2");
        vm.label(users.institution3, "Institution3");
        vm.label(users.institution4, "Institution4");
    }
}
