

pragma solidity >=0.5.0 <0.6.0;

import "openzeppelin-solidity/contracts/math/SafeMath.sol";

import "./ZkAsset.sol";
import "../ACE/ACE.sol";
import "../ERC20/ERC20Mintable.sol";
import "../libs/LibEIP712.sol";
import "../libs/ProofUtils.sol";
import "./ZkAssetOwnable.sol";


contract ZkAssetMintable is ZkAssetOwnable {
    event UpdateTotalMinted(bytes32 noteHash, bytes noteData);
    address public owner;

    constructor(
        address _aceAddress,
        address _linkedTokenAddress,
        uint256 _scalingFactor,
        bool _canAdjustSupply,
        bool _canConvert
    ) public ZkAssetOwnable(
        _aceAddress,
        _linkedTokenAddress,
        _scalingFactor,
        _canAdjustSupply,
        _canConvert
    ) {
        owner = msg.sender;
    }

    function confidentialMint(uint24 _proof, bytes calldata _proofData) external {
        require(msg.sender == owner, "only the owner can call the confidentialMint() method");
        require(_proofData.length != 0, "proof invalid");

        (bytes memory _proofOutputs) = ace.mint(_proof, _proofData, address(this));

        (, bytes memory newTotal, ,) = _proofOutputs.get(0).extractProofOutput();

        (, bytes memory mintedNotes, ,) = _proofOutputs.get(1).extractProofOutput();

        (,
        bytes32 noteHash,
        bytes memory metadata) = newTotal.get(0).extractNote();

        logOutputNotes(mintedNotes);
        emit UpdateTotalMinted(noteHash, metadata);
    }

    function confidentialTransfer(bytes memory _proofData) public {
        bytes memory proofOutputs = ace.validateProof(JOIN_SPLIT_PROOF, msg.sender, _proofData);
        require(proofOutputs.length != 0, "proof invalid");

        bytes memory proofOutput = proofOutputs.get(0);

        (,
        ,
        ,
        int256 publicValue) = proofOutput.extractProofOutput();

        (
            ,
            uint256 scalingFactor,
            uint256 totalSupply,
            ,
            ,
            ,
        ) = ace.getRegistry(address(this));
        if (publicValue > 0) {
            if (totalSupply < uint256(publicValue)) {
                uint256 supplementValue = uint256(publicValue).sub(totalSupply);
                ERC20Mintable(address(linkedToken)).mint(address(this), supplementValue.mul(scalingFactor));
                ERC20Mintable(address(linkedToken)).approve(address(ace), supplementValue.mul(scalingFactor));

                ace.supplementTokens(supplementValue);
            }
        }

        confidentialTransferInternal(proofOutputs);
    }

    function confidentialTransferFrom(uint24 _proof, bytes memory _proofOutput) public {
        (bytes memory inputNotes,
        bytes memory outputNotes,
        address publicOwner,
        int256 publicValue) = _proofOutput.extractProofOutput();
        
        uint256 length = inputNotes.getLength();
        for (uint i = 0; i < length; i += 1) {
            (, bytes32 noteHash, ) = inputNotes.get(i).extractNote();
            require(
                confidentialApproved[noteHash][msg.sender] == true,
                "sender does not have approval to spend input note"
            );
        }

        (
            ,
            uint256 scalingFactor,
            uint256 totalSupply,
            ,
            ,
            ,
        ) = ace.getRegistry(address(this));

        if (publicValue > 0) {
            if (totalSupply < uint256(publicValue)) {
                uint256 supplementValue = uint256(publicValue).sub(totalSupply);
                ERC20Mintable(address(linkedToken)).mint(address(this), supplementValue.mul(scalingFactor));
                ERC20Mintable(address(linkedToken)).approve(address(ace), supplementValue.mul(scalingFactor));

                ace.supplementTokens(supplementValue);
            }
        }


        ace.updateNoteRegistry(_proof, _proofOutput, msg.sender);

        logInputNotes(inputNotes);
        logOutputNotes(outputNotes);

        if (publicValue < 0) {
            emit ConvertTokens(publicOwner, uint256(-publicValue));
        }
        if (publicValue > 0) {
            emit RedeemTokens(publicOwner, uint256(publicValue));
        }
    }
}

