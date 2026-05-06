# ERC721Holder
[Git Source](https://github.com/VerisLabs/KAM/blob/447168c958315cdee5506bbde566ae1376e64d18/src/vendor/openzeppelin/token/ERC721/utils/ERC721Holder.sol)

**Inherits:**
[IERC721Receiver](/Users/filipe.venancio/Documents/GitHub/KAM/foundry-docs/src/src/vendor/openzeppelin/token/ERC721/IERC721Receiver.sol/interface.IERC721Receiver.md)

Implementation of the {IERC721Receiver} interface.
Accepts all token transfers.
Make sure the contract is able to use its token with [IERC721-safeTransferFrom](//Users/filipe.venancio/Documents/GitHub/KAM/foundry-docs/src/dependencies/kToken0-1.0/src/vendor/solady/utils/SafeTransferLib.sol/library.SafeTransferLib.md#safetransferfrom), [IERC721-approve](//Users/filipe.venancio/Documents/GitHub/KAM/foundry-docs/src/src/interfaces/IkStakingVault.sol/interface.IkStakingVault.md#approve) or
{IERC721-setApprovalForAll}.

**Note:**
stateless: 


## Functions
### onERC721Received

See [IERC721Receiver-onERC721Received](//Users/filipe.venancio/Documents/GitHub/KAM/foundry-docs/src/dependencies/minimal-smart-account-1.0/src/MinimalSmartAccount.sol/contract.MinimalSmartAccount.md#onerc721received).
Always returns `IERC721Receiver.onERC721Received.selector`.


```solidity
function onERC721Received(address, address, uint256, bytes memory) public virtual returns (bytes4);
```

