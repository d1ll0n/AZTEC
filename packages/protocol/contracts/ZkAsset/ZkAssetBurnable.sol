

pragma solidity >=0.5.0 <0.6.0;

import "openzeppelin-solidity/contracts/math/SafeMath.sol";

import "../ACE/ACE.sol";
import "../libs/LibEIP712.sol";
import "../libs/ProofUtils.sol";
import "./base/ZkAssetOwnableBase.sol";

contract ZkAssetBurnable is ZkAssetOwnableBase {
    event UpdateTotalBurned(bytes32 noteHash, bytes noteData);

    constructor(
        address _aceAddress,
        address _linkedTokenAddress,
        uint256 _scalingFactor
    ) public ZkAssetOwnableBase(
        _aceAddress,
        _linkedTokenAddress,
        _scalingFactor,
        true // canAdjustSupply
    ) {
    }

    function confidentialBurn(uint24 _proof, bytes calldata _proofData) external onlyOwner {
        require(_proofData.length != 0, "proof invalid");

        (bytes memory _proofOutputs) = ace.burn(_proof, _proofData, address(this));

        (, bytes memory newTotal, ,) = _proofOutputs.get(0).extractProofOutput();

        (, bytes memory burnedNotes, ,) = _proofOutputs.get(1).extractProofOutput();

        (,
        bytes32 noteHash,
        bytes memory metadata) = newTotal.get(0).extractNote();

        logOutputNotes(burnedNotes);
        emit UpdateTotalBurned(noteHash, metadata);
    }
}


