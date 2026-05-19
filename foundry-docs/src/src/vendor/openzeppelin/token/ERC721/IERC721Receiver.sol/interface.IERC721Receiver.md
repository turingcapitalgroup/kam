# IERC721Receiver
[Git Source](https://github.com/VerisLabs/KAM/blob/447168c958315cdee5506bbde566ae1376e64d18/src/vendor/openzeppelin/token/ERC721/IERC721Receiver.sol)

Interface for any contract that wants to support safeTransfers
from ERC-721 asset contracts.


## Functions
### onERC721Received

Whenever an {IERC721} `tokenId` token is transferred to this contract via [IERC721-safeTransferFrom](//Users/filipe.venancio/Documents/GitHub/KAM/foundry-docs/src/dependencies/kToken0-1.0/src/vendor/solady/utils/SafeTransferLib.sol/library.SafeTransferLib.md#safetransferfrom)
by `operator` from `from`, this function is called.
It must return its Solidity selector to confirm the token transfer.
If any other value is returned or the interface is not implemented by the recipient, the transfer will be
reverted.
The selector can be obtained in Solidity with `IERC721Receiver.onERC721Received.selector`.


```solidity
function onERC721Received(
    address operator,
    address from,
    uint256 tokenId,
    bytes calldata data
)
    external
    returns (bytes4);
```

