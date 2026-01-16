// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import { SetUp } from "kam/test/invariant/helpers/SetUp.t.sol";

contract kStakingVaultInvariants is SetUp {
    function setUp() public override {
        _setUp();
        _setUpkStakingVaultHandlerAlpha();
        _setUpInstitutionalMint();
        _setUpVaultFees(alphaVault);
    }

    function invariant_kStakingVaultTotalAssets() public view {
        vaultHandlerAlpha.INVARIANT_A_TOTAL_ASSETS();
    }

    function invariant_kStakingVaultAdapterBalance() public view {
        vaultHandlerAlpha.INVARIANT_B_ADAPTER_BALANCE();
    }

    function invariant_kStakingVaultAdapterTotalAssets() public view {
        vaultHandlerAlpha.INVARIANT_C_ADAPTER_TOTAL_ASSETS();
    }

    function invariant_kStakingVaultSharePrice() public view {
        vaultHandlerAlpha.INVARIANT_D_SHARE_PRICE();
    }

    function invariant_kStakingVaultTotalNetAssets() public view {
        vaultHandlerAlpha.INVARIANT_E_TOTAL_NET_ASSETS();
    }

    function invariant_kStakingVaultSupply() public view {
        vaultHandlerAlpha.INVARIANT_F_SUPPLY();
    }

    function invariant_kStakingVaultSharePriceDelta() public view {
        vaultHandlerAlpha.INVARIANT_G_SHARE_PRICE_DELTA();
    }

    function invariant_kStakingVaultClaimStableSharePrice() public view {
        vaultHandlerAlpha.INVARIANT_H_CLAIM_STABLE_SHARE_PRICE();
    }

    function invariant_kStakingVaultPendingStakeSettlement() public view {
        vaultHandlerAlpha.INVARIANT_I_PENDING_STAKE_SETTLEMENT();
    }

    function invariant_kStakingVaultUnstakeClaimAccuracy() public view {
        vaultHandlerAlpha.INVARIANT_J_UNSTAKE_CLAIM_ACCURACY();
    }

    function invariant_kStakingVaultFeeBounds() public view {
        vaultHandlerAlpha.INVARIANT_K_FEE_BOUNDS();
    }

    function invariant_kStakingVaultSelfBalance() public view {
        vaultHandlerAlpha.INVARIANT_L_VAULT_SELF_BALANCE();
    }
}
