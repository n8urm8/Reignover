// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "./libs/Editor.sol";

contract ResourceToken is ERC20Burnable, Editor {

    // thoughts, should I implement a transfer delay? Is the anti-flash loan measure worth all the extra work? 
    // do flash loans even have a negative impact?
    
    constructor(string memory name_, string memory symbol_) ERC20(name_, symbol_) {}

    /** @notice mint function for editors, used by resource manager */
    function mint(address _to, uint _amount) external onlyEditor {
        _mint(_to, _amount);
    }
    
}