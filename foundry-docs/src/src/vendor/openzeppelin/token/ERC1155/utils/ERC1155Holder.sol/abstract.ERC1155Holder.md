# ERC1155Holder
[Git Source](https://github.com/turingcapitalgroup/kam/blob/ff596cc04152c6a76cd4f835891a09e2edadf4e9/src/vendor/openzeppelin/token/ERC1155/utils/ERC1155Holder.sol)

**Inherits:**
[ERC165](/home/solthodox/Documentos/keyrock/kam/foundry-docs/src/src/vendor/openzeppelin/utils/introspection/ERC165.sol/abstract.ERC165.md), [IERC1155Receiver](/home/solthodox/Documentos/keyrock/kam/foundry-docs/src/src/vendor/openzeppelin/token/ERC1155/IERC1155Receiver.sol/interface.IERC1155Receiver.md)

Simple implementation of `IERC1155Receiver` that will allow a contract to hold ERC-1155 tokens.
IMPORTANT: When inheriting this contract, you must include a way to use the received tokens, otherwise they will be
stuck.

**Note:**
stateless: 


## Functions
### supportsInterface

Returns true if this contract implements the interface defined by
`interfaceId`. See the corresponding
https://eips.ethereum.org/EIPS/eip-165#how-interfaces-are-identified[ERC section]
to learn more about how these ids are created.
This function call must use less than 30 000 gas.


```solidity
function supportsInterface(bytes4 interfaceId) public view virtual override(ERC165, IERC165) returns (bool);
```

### onERC1155Received


```solidity
function onERC1155Received(
    address,
    address,
    uint256,
    uint256,
    bytes memory
)
    public
    virtual
    override
    returns (bytes4);
```

### onERC1155BatchReceived


```solidity
function onERC1155BatchReceived(
    address,
    address,
    uint256[] memory,
    uint256[] memory,
    bytes memory
)
    public
    virtual
    override
    returns (bytes4);
```

