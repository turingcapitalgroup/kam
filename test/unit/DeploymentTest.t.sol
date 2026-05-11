// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import { ADMIN_ROLE, INSTITUTION_ROLE, MINTER_ROLE, _1_USDC, _1_WBTC } from "../utils/Constants.sol";

import { DeploymentBaseTest } from "../utils/DeploymentBaseTest.sol";

import { IERC20 } from "forge-std/interfaces/IERC20.sol";
import { IERC4626 } from "forge-std/interfaces/IERC4626.sol";
import { ConfigureAdapterApprovalsScript } from "kam/script/deployment/12_ConfigureAdapterApprovals.s.sol";
import { IRegistry } from "kam/src/interfaces/IRegistry.sol";
import { IExecutionGuardian } from "kam/src/interfaces/modules/IExecutionGuardian.sol";
import { OptimizedOwnableRoles } from "solady/auth/OptimizedOwnableRoles.sol";

contract DeploymentTest is DeploymentBaseTest {
    function test_ProtocolDeployment() public view {
        assertTrue(address(registry) != address(0), "Registry not deployed");
        assertTrue(address(assetRouter) != address(0), "AssetRouter not deployed");
        assertTrue(address(kUSD) != address(0), "kUSD not deployed");
        assertTrue(address(kBTC) != address(0), "kBTC not deployed");
        assertTrue(address(minter) != address(0), "Minter not deployed");
        assertTrue(address(dnVault) != address(0), "DN Vault not deployed");
        assertTrue(address(alphaVault) != address(0), "Alpha Vault not deployed");
        assertTrue(address(betaVault) != address(0), "Beta Vault not deployed");

        assertTrue(address(registryImpl) != address(0), "Registry impl not deployed");
        assertTrue(address(assetRouterImpl) != address(0), "AssetRouter impl not deployed");
        assertTrue(address(minterImpl) != address(0), "Minter impl not deployed");
        assertTrue(address(stakingVaultImpl) != address(0), "StakingVault impl not deployed");
    }

    function test_ProtocolInitialization() public view {
        assertProtocolInitialized();
    }

    function test_TokenProperties() public view {
        assertEq(kUSD.name(), KUSD_NAME, "kUSD name incorrect");
        assertEq(kUSD.symbol(), KUSD_SYMBOL, "kUSD symbol incorrect");
        assertEq(kUSD.decimals(), 6, "kUSD decimals incorrect");

        assertEq(kBTC.name(), KBTC_NAME, "kBTC name incorrect");
        assertEq(kBTC.symbol(), KBTC_SYMBOL, "kBTC symbol incorrect");
        assertEq(kBTC.decimals(), 8, "kBTC decimals incorrect");

        assertEq(dnVault.name(), DN_VAULT_NAME, "DN Vault name incorrect");
        assertEq(dnVault.symbol(), DN_VAULT_SYMBOL, "DN Vault symbol incorrect");
        assertEq(dnVault.decimals(), 6, "DN Vault decimals incorrect");

        assertEq(alphaVault.name(), ALPHA_VAULT_NAME, "Alpha Vault name incorrect");
        assertEq(alphaVault.symbol(), ALPHA_VAULT_SYMBOL, "Alpha Vault symbol incorrect");
        assertEq(alphaVault.decimals(), 6, "Alpha Vault decimals incorrect");

        assertEq(betaVault.name(), BETA_VAULT_NAME, "Beta Vault name incorrect");
        assertEq(betaVault.symbol(), BETA_VAULT_SYMBOL, "Beta Vault symbol incorrect");
        assertEq(betaVault.decimals(), 6, "Beta Vault decimals incorrect");
    }

    function test_RoleAssignments() public view {
        assertHasRole(address(registry), users.admin, ADMIN_ROLE);
        assertHasRole(address(kUSD), users.admin, ADMIN_ROLE);
        assertHasRole(address(kBTC), users.admin, ADMIN_ROLE);
        assertHasRole(address(registry), users.institution, INSTITUTION_ROLE);

        assertHasRole(address(kUSD), address(minter), MINTER_ROLE);
        assertHasRole(address(kBTC), address(minter), MINTER_ROLE);

        assertHasRole(address(kUSD), address(assetRouter), MINTER_ROLE);
        assertHasRole(address(kBTC), address(assetRouter), MINTER_ROLE);

        assertFalse(
            OptimizedOwnableRoles(address(kUSD)).hasAnyRole(address(dnVault), MINTER_ROLE),
            "DN vault should not have kToken MINTER_ROLE"
        );
        assertFalse(
            OptimizedOwnableRoles(address(kUSD)).hasAnyRole(address(alphaVault), MINTER_ROLE),
            "Alpha vault should not have kToken MINTER_ROLE"
        );
        assertFalse(
            OptimizedOwnableRoles(address(kUSD)).hasAnyRole(address(betaVault), MINTER_ROLE),
            "Beta vault should not have kToken MINTER_ROLE"
        );
    }

    function test_AssetRegistration() public view {
        assertTrue(registry.isAsset(tokens.usdc), "tokens.usdc not registered");
        assertEq(registry.assetToKToken(tokens.usdc), address(kUSD), "USDC->kUSD mapping incorrect");

        assertTrue(registry.isAsset(tokens.wbtc), "WBTC not registered");
        assertEq(registry.assetToKToken(tokens.wbtc), address(kBTC), "WBTC->kBTC mapping incorrect");
    }

    function test_VaultRegistration() public view {
        assertTrue(registry.isVault(address(minter)), "Minter Vault not registered");
        assertTrue(registry.isVault(address(dnVault)), "DN Vault not registered");
        assertTrue(registry.isVault(address(alphaVault)), "Alpha Vault not registered");
        assertTrue(registry.isVault(address(betaVault)), "Beta Vault not registered");

        assertEq(registry.getVaultAssets(address(dnVault))[0], tokens.usdc, "DN Vault asset mapping incorrect");
        assertEq(registry.getVaultAssets(address(alphaVault))[0], tokens.usdc, "Alpha Vault asset mapping incorrect");
        assertEq(registry.getVaultAssets(address(betaVault))[0], tokens.usdc, "Beta Vault asset mapping incorrect");

        assertEq(registry.getVaultType(address(minter)), uint8(0), "Minter Vault type incorrect"); // Minter = 0
        assertEq(registry.getVaultType(address(dnVault)), uint8(1), "DN Vault type incorrect"); // DN = 1
        assertEq(registry.getVaultType(address(alphaVault)), uint8(2), "Alpha Vault type incorrect"); // ALPHA = 2
        assertEq(registry.getVaultType(address(betaVault)), uint8(3), "Beta Vault type incorrect"); // BETA = 3
    }

    function test_deployAdapter_namespaces_fromConfig() public view {
        assertEq(minterAdapterUSDC.accountId(), "kam.minter.usdc", "kMinter USDC adapter namespace incorrect");
        assertEq(minterAdapterWBTC.accountId(), "kam.minter.wbtc", "kMinter WBTC adapter namespace incorrect");
        assertEq(DNVaultAdapterUSDC.accountId(), "kam.dnVault.usdc", "DN USDC adapter namespace incorrect");
        assertEq(ALPHAVaultAdapterUSDC.accountId(), "kam.alphaVault.usdc", "Alpha adapter namespace incorrect");
        assertEq(BETHAVaultAdapterUSDC.accountId(), "kam.betaVault.usdc", "Beta adapter namespace incorrect");
    }

    function test_configureProtocol_vaultType_fromConfig() public view {
        assertEq(registry.getVaultType(address(minter)), uint8(IRegistry.VaultType.MINTER), "Minter type incorrect");
        assertEq(registry.getVaultType(address(dnVault)), uint8(IRegistry.VaultType.DN), "DN type incorrect");
        assertEq(registry.getVaultType(address(alphaVault)), uint8(IRegistry.VaultType.ALPHA), "Alpha type incorrect");
        assertEq(registry.getVaultType(address(betaVault)), uint8(IRegistry.VaultType.BETA), "Beta type incorrect");
    }

    function test_configureProtocol_vaultAssetPairing_fromConfig() public view {
        assertEq(
            registry.getVaultByAssetAndType(tokens.usdc, uint8(IRegistry.VaultType.DN)),
            address(dnVault),
            "DN USDC pairing incorrect"
        );
        assertEq(
            registry.getVaultByAssetAndType(tokens.wbtc, uint8(IRegistry.VaultType.DN)),
            _vaultsDeploy.dnVaultWBTC,
            "DN WBTC pairing incorrect"
        );
        assertEq(
            registry.getVaultByAssetAndType(tokens.usdc, uint8(IRegistry.VaultType.ALPHA)),
            address(alphaVault),
            "Alpha asset pairing incorrect"
        );
        assertEq(
            registry.getVaultByAssetAndType(tokens.usdc, uint8(IRegistry.VaultType.BETA)),
            address(betaVault),
            "Beta asset pairing incorrect"
        );
    }

    function test_insuranceBps_applied_orRemoved() public view {
        assertEq(registry.getTreasuryBps(), 1000, "Treasury BPS not applied");
        assertEq(registry.getInsuranceBps(), 500, "Insurance BPS not applied");
    }

    function test_configureProtocol_vaultBatchLimits_fromConfig() public view {
        assertEq(registry.getMaxMintPerBatch(address(dnVault)), type(uint256).max, "DN USDC deposit limit incorrect");
        assertEq(registry.getMaxBurnPerBatch(address(dnVault)), 50_000_000_000_000, "DN USDC withdraw limit incorrect");
        assertEq(
            registry.getMaxMintPerBatch(_vaultsDeploy.dnVaultWBTC), type(uint256).max, "DN WBTC deposit limit incorrect"
        );
        assertEq(
            registry.getMaxBurnPerBatch(_vaultsDeploy.dnVaultWBTC), 2_000_000_000, "DN WBTC withdraw limit incorrect"
        );
        assertEq(registry.getMaxMintPerBatch(address(alphaVault)), type(uint256).max, "Alpha deposit limit incorrect");
        assertEq(registry.getMaxBurnPerBatch(address(alphaVault)), 20_000_000_000_000, "Alpha withdraw limit incorrect");
    }

    function test_configureAdapterApprovals_revokesTemporaryManagerRole() public {
        assertFalse(registry.isManager(users.admin), "admin should not start as manager");

        ConfigureAdapterApprovalsScript approvalsScript = new ConfigureAdapterApprovalsScript();
        approvalsScript.setVerbose(false);
        approvalsScript.run(
            address(registry),
            address(minterAdapterUSDC),
            address(minterAdapterWBTC),
            address(DNVaultAdapterUSDC),
            _adaptersDeploy.dnVaultAdapterWBTC,
            address(ALPHAVaultAdapterUSDC),
            address(BETHAVaultAdapterUSDC),
            address(metawalletUSDC),
            address(metawalletWBTC)
        );

        assertFalse(registry.isManager(users.admin), "temporary manager role should be revoked");
    }

    function test_configureExecutorPermissions_rawAllowedSources_fromConfig() public view {
        assertTrue(
            erc20ExecutionValidator.isAllowedSource(tokens.usdc, address(minterAdapterUSDC)),
            "USDC minter adapter source not applied"
        );
        assertTrue(
            erc20ExecutionValidator.isAllowedSource(tokens.usdc, address(DNVaultAdapterUSDC)),
            "USDC DN adapter source not applied"
        );
        assertTrue(
            erc20ExecutionValidator.isAllowedSource(tokens.wbtc, address(minterAdapterWBTC)),
            "WBTC minter adapter source not applied"
        );
        assertTrue(
            erc20ExecutionValidator.isAllowedSource(tokens.wbtc, users.treasury), "WBTC treasury source not applied"
        );
    }

    function test_UserFunding() public view {
        assertEq(getAssetBalance(tokens.usdc, users.alice), 1_000_000 * _1_USDC, "Alice USDC balance incorrect");
        assertEq(getAssetBalance(tokens.usdc, users.bob), 500_000 * _1_USDC, "Bob USDC balance incorrect");
        assertEq(
            getAssetBalance(tokens.usdc, users.institution),
            10_000_000 * _1_USDC,
            "Institution tokens.usdc balance incorrect"
        );

        assertEq(getAssetBalance(tokens.wbtc, users.alice), 100 * _1_WBTC, "Alice WBTC balance incorrect");
        assertEq(getAssetBalance(tokens.wbtc, users.bob), 50 * _1_WBTC, "Bob WBTC balance incorrect");
        assertEq(getAssetBalance(tokens.wbtc, users.institution), 1000 * _1_WBTC, "Institution WBTC balance incorrect");
    }

    function test_BasicMinting() public {
        uint256 mintAmount = 1000 * _1_USDC;

        mintKTokens(address(kUSD), users.alice, mintAmount);

        assertKTokenBalance(address(kUSD), users.alice, mintAmount);

        assertEq(kUSD.totalSupply(), mintAmount, "Total supply incorrect");
    }

    function test_ContractOwnership() public view {
        assertEq(registry.owner(), users.owner, "Registry owner incorrect");
        assertEq(kUSD.owner(), users.owner, "kUSD owner incorrect");
        assertEq(kBTC.owner(), users.owner, "kBTC owner incorrect");
        assertEq(dnVault.owner(), users.owner, "DN Vault owner incorrect");
        assertEq(alphaVault.owner(), users.owner, "Alpha Vault owner incorrect");
        assertEq(betaVault.owner(), users.owner, "Beta Vault owner incorrect");
    }

    function test_ProtocolState() public view {
        (
            address registryAddr,
            address assetRouterAddr,
            address kUSDAddr,
            address kBTCAddr,
            address minterAddr,
            address dnVaultAddr,
            address alphaVaultAddr,
            address betaVaultAddr
        ) = getProtocolState();

        assertEq(registryAddr, address(registry), "Registry address mismatch");
        assertEq(assetRouterAddr, address(assetRouter), "AssetRouter address mismatch");
        assertEq(kUSDAddr, address(kUSD), "kUSD address mismatch");
        assertEq(kBTCAddr, address(kBTC), "kBTC address mismatch");
        assertEq(minterAddr, address(minter), "Minter address mismatch");
        assertEq(dnVaultAddr, address(dnVault), "DN Vault address mismatch");
        assertEq(alphaVaultAddr, address(alphaVault), "Alpha Vault address mismatch");
        assertEq(betaVaultAddr, address(betaVault), "Beta Vault address mismatch");
    }

    function test_PauseUnpause() public {
        assertFalse(kUSD.isPaused(), "kUSD should be unpaused");

        vm.prank(users.emergencyAdmin);
        kUSD.setPaused(true);

        assertTrue(kUSD.isPaused(), "kUSD should be paused");

        vm.prank(users.emergencyAdmin);
        kUSD.setPaused(false);

        assertFalse(kUSD.isPaused(), "kUSD should be unpaused");
    }

    function test_VaultTypeHelper() public view {
        assertEq(address(getVaultByType(IRegistry.VaultType.DN)), address(dnVault), "DN vault helper incorrect");
        assertEq(
            address(getVaultByType(IRegistry.VaultType.ALPHA)), address(alphaVault), "Alpha vault helper incorrect"
        );
        assertEq(address(getVaultByType(IRegistry.VaultType.BETA)), address(betaVault), "Beta vault helper incorrect");
    }

    function test_ExecutionValidatorsMatchProductionPaths() public view {
        IExecutionGuardian guardian = IExecutionGuardian(address(registry));

        address erc20Validator =
            guardian.getExecutionValidator(address(minterAdapterUSDC), tokens.usdc, IERC20.approve.selector);
        address erc4626Validator = guardian.getExecutionValidator(
            address(minterAdapterUSDC), address(metawalletUSDC), IERC4626.deposit.selector
        );

        assertTrue(erc20Validator != address(0), "ERC20 validator not configured");
        assertTrue(erc4626Validator != address(0), "ERC4626 validator not configured");
        assertTrue(erc20Validator != erc4626Validator, "validators must be distinct");

        assertEq(
            guardian.getExecutionValidator(
                address(minterAdapterUSDC), address(metawalletUSDC), IERC4626.deposit.selector
            ),
            erc4626Validator,
            "kMinter deposit should use ERC4626 validator"
        );
        assertEq(
            guardian.getExecutionValidator(
                address(minterAdapterUSDC), address(metawalletUSDC), IERC4626.withdraw.selector
            ),
            erc4626Validator,
            "kMinter withdraw should use ERC4626 validator"
        );
        assertFalse(
            guardian.isSelectorAllowed(address(minterAdapterUSDC), address(metawalletUSDC), IERC4626.redeem.selector),
            "kMinter redeem should not be allowed"
        );
        assertFalse(
            guardian.isSelectorAllowed(
                address(minterAdapterUSDC), address(metawalletUSDC), IERC20.transferFrom.selector
            ),
            "kMinter metawallet transferFrom should not be allowed"
        );

        assertEq(
            guardian.getExecutionValidator(
                address(DNVaultAdapterUSDC), address(metawalletUSDC), IERC20.transfer.selector
            ),
            erc20Validator,
            "DN transfer should use ERC20 validator"
        );
        assertEq(
            guardian.getExecutionValidator(
                address(DNVaultAdapterUSDC), address(metawalletUSDC), IERC20.transferFrom.selector
            ),
            erc20Validator,
            "DN transferFrom should use ERC20 validator"
        );
    }
}
