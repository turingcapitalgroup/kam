// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import { SetUp } from "kam/test/invariant/helpers/SetUp.t.sol";

contract IntegrationInvariants is SetUp {
    function setUp() public override {
        useMinter = true;
        _setUp();
        _setUpkMinterHandler();
        _setUpInstitutionalMint();
        _setUpkStakingVaultHandlerDeltaNeutral();
        _setUpkStakingVaultHandlerAlpha();
        _setUpkStakingVaultHandlerBeta();
        _setUpVaultFees(dnVault);
        _setUpVaultFees(alphaVault);
        _setUpVaultFees(betaVault);
    }

    function invariant_INTEGRATION_kMinterLockedAssets() public view {
        minterHandler.INVARIANT_A_TOTAL_LOCKED_ASSETS();
    }

    function invariant_INTEGRATION_kMinterAdapterBalance() public view {
        minterHandler.INVARIANT_B_ADAPTER_BALANCE();
    }

    function invariant_INTEGRATION_kMinterAdapterTotalAssets() public view {
        minterHandler.INVARIANT_C_ADAPTER_TOTAL_ASSETS();
    }

    function invariant_INTEGRATION_kStakingVaultTotalAssets() public view {
        vaultHandlerDeltaNeutral.INVARIANT_A_TOTAL_ASSETS();
        vaultHandlerAlpha.INVARIANT_A_TOTAL_ASSETS();
        vaultHandlerBeta.INVARIANT_A_TOTAL_ASSETS();
    }

    function invariant_INTEGRATION_kStakingVaultAdapterBalance() public view {
        vaultHandlerDeltaNeutral.INVARIANT_B_ADAPTER_BALANCE();
        vaultHandlerAlpha.INVARIANT_B_ADAPTER_BALANCE();
        vaultHandlerBeta.INVARIANT_B_ADAPTER_BALANCE();
    }

    function invariant_INTEGRATION_kStakingVaultAdapterTotalAssets() public view {
        vaultHandlerDeltaNeutral.INVARIANT_C_ADAPTER_TOTAL_ASSETS();
        vaultHandlerAlpha.INVARIANT_C_ADAPTER_TOTAL_ASSETS();
        vaultHandlerBeta.INVARIANT_C_ADAPTER_TOTAL_ASSETS();
    }

    function invariant_INTEGRATION_kStakingVaultSharePrice() public view {
        vaultHandlerDeltaNeutral.INVARIANT_D_SHARE_PRICE();
        vaultHandlerAlpha.INVARIANT_D_SHARE_PRICE();
        vaultHandlerBeta.INVARIANT_D_SHARE_PRICE();
    }

    function invariant_INTEGRATION_kStakingVaultTotalNetAssets() public view {
        vaultHandlerDeltaNeutral.INVARIANT_E_TOTAL_NET_ASSETS();
        vaultHandlerAlpha.INVARIANT_E_TOTAL_NET_ASSETS();
        vaultHandlerBeta.INVARIANT_E_TOTAL_NET_ASSETS();
    }

    function invariant_INTEGRATION_kStakingVaultSupply() public view {
        vaultHandlerDeltaNeutral.INVARIANT_F_SUPPLY();
        vaultHandlerAlpha.INVARIANT_F_SUPPLY();
        vaultHandlerBeta.INVARIANT_F_SUPPLY();
    }

    function invariant_INTEGRATION_kStakingVaultSharePriceDelta() public view {
        vaultHandlerDeltaNeutral.INVARIANT_G_SHARE_PRICE_DELTA();
        vaultHandlerAlpha.INVARIANT_G_SHARE_PRICE_DELTA();
        vaultHandlerBeta.INVARIANT_G_SHARE_PRICE_DELTA();
    }
}
