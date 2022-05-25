// SPDX-License-Identifier: MIT

pragma solidity ^0.8.7;

import "@openzeppelin/contracts/access/Ownable.sol";
contract Editor is Ownable {

    mapping (address => bool) public editor;

    event NewEditor(address editor);
    event RemovedEditor(address editor);
    
    modifier onlyEditor {
        require(editor[msg.sender] == true);
        _;
    }
     // Add new editors
    function addEditor(address _editor) external onlyOwner {
        require(editor[_editor] == false, "Address is already editor");
        editor[_editor] = true;
        emit NewEditor(_editor);
    }
    // Deactivate a editor
    function deactivateEditor ( address _editor) public onlyOwner {
        require(editor[_editor] == true, "Address is not editor");
        editor[_editor] = false;
        emit RemovedEditor(_editor);
    }

}