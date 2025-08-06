// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Burnable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract ERC721Test is ERC721, ERC721Burnable, Ownable {

    string baseUri;

    constructor(address initialOwner, string memory _baseUri)
        ERC721("MyToken", "MTK")
        Ownable(initialOwner)
    {
        baseUri = _baseUri;
    }

    function safeMint(address to, uint256 tokenId) public onlyOwner {
        _safeMint(to, tokenId);
    }

    function _baseURI() internal view override returns (string memory) {
        return baseUri;
    }
}
