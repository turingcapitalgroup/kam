# ERC165
[Git Source](https://github.com/turingcapitalgroup/kam/blob/ff596cc04152c6a76cd4f835891a09e2edadf4e9/src/vendor/openzeppelin/utils/introspection/ERC165.sol)

**Inherits:**
[IERC165](/home/solthodox/Documentos/keyrock/kam/foundry-docs/src/src/vendor/openzeppelin/utils/introspection/IERC165.sol/interface.IERC165.md)

Implementation of the {IERC165} interface.
Contracts that want to implement ERC-165 should inherit from this contract and override [supportsInterface](//home/solthodox/Documentos/keyrock/kam/foundry-docs/src/src/vendor/openzeppelin/utils/introspection/ERC165.sol/abstract.ERC165.md#supportsinterface) to check
for the additional interface id that will be supported. For example:
```solidity
function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
return interfaceId == type(MyInterface).interfaceId || super.supportsInterface(interfaceId);
}
```


## Functions
### supportsInterface

Returns true if this contract implements the interface defined by
`interfaceId`. See the corresponding
https://eips.ethereum.org/EIPS/eip-165#how-interfaces-are-identified[ERC section]
to learn more about how these ids are created.
This function call must use less than 30 000 gas.


```solidity
function supportsInterface(bytes4 interfaceId) public view virtual returns (bool);
```

