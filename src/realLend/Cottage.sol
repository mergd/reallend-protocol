// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {LibString} from "solmate/utils/LibString.sol";
import {ERC721} from "solmate/tokens/ERC721.sol";

contract Cottage is ERC721 {
    using LibString for uint256;
    string public _tokenURI;
    constructor() ERC721("Vacation Cottage", "VC") {}

    function mint(address to, uint256 id) external {
        _mint(to, id);
    }

    function tokenURI(uint256 id) public view override returns (string memory) {
        return string.concat(_tokenURI, id.toString());
    }

    function setTokenURI(uint256 id, string memory uri) external {
        _tokenURI = uri;
    }
}
