# ERC721Holder
[Git Source](https://github.com/turingcapitalgroup/kam/blob/ff596cc04152c6a76cd4f835891a09e2edadf4e9/src/vendor/openzeppelin/token/ERC721/utils/ERC721Holder.sol)

**Inherits:**
[IERC721Receiver](/home/solthodox/Documentos/keyrock/kam/foundry-docs/src/src/vendor/openzeppelin/token/ERC721/IERC721Receiver.sol/interface.IERC721Receiver.md)

Implementation of the {IERC721Receiver} interface.
Accepts all token transfers.
Make sure the contract is able to use its token with [IERC721-safeTransferFrom](//home/solthodox/Documentos/keyrock/kam/foundry-docs/src/dependencies/kToken0-1.0/src/vendor/solady/utils/SafeTransferLib.sol/library.SafeTransferLib.md#safetransferfrom), [IERC721-approve](//home/solthodox/Documentos/keyrock/kam/foundry-docs/src/src/interfaces/IkStakingVault.sol/interface.IkStakingVault.md#approve) or
{IERC721-setApprovalForAll}.

**Note:**
stateless: 


## Functions
### onERC721Received

See [IERC721Receiver-onERC721Received](//home/solthodox/Documentos/keyrock/kam/foundry-docs/src/src/vendor/openzeppelin/token/ERC721/IERC721Receiver.sol/interface.IERC721Receiver.md#onerc721received).
Always returns `IERC721Receiver.onERC721Received.selector`.


```solidity
function onERC721Received(address, address, uint256, bytes memory) public virtual returns (bytes4);
```

