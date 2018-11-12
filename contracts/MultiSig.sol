pragma solidity ^0.4.24;

import "./open-zeppelin/SafeMath.sol";

/// @title MultiSignature Owner Controls
contract MultiSig {

	using SafeMath64 for uint64;

	bytes32 ownerID;
	mapping (address => Address) idMap;
	mapping (bytes32 => Authority) authorityData;

	struct Address {
		bytes32 id;
		bool restricted;
	}

	struct Authority {
		mapping (bytes4 => bool) signatures;
		mapping (bytes32 => address[]) multiSigAuth;
		uint64 multiSigThreshold;
		uint64 addressCount;
		uint64 approvedUntil;
	}

	event MultiSigCall (
		bytes32 indexed id,
		bytes4 indexed callSignature,
		bytes32 indexed callHash,
		address caller,
		uint256 callCount,
		uint256 threshold
	);
	event MultiSigCallApproved (
		bytes32 indexed id,
		bytes4 indexed callSignature,
		bytes32 indexed callHash,
		address caller
	);
	event NewAuthority (
		bytes32 indexed id,
		uint64 approvedUntil,
		uint64 threshold
	);
	event ApprovedUntilSet (bytes32 indexed id, uint64 approvedUntil);
	event ThresholdSet (bytes32 indexed id, uint64 threshold);
	event NewAuthorityPermissions (bytes32 indexed id, bytes4[] signatures);
	event RemovedAuthorityPermissions (bytes32 indexed id, bytes4[] signatures);
	event NewAuthorityAddresses (
		bytes32 indexed id,
		address[] added,
		uint64 ownerCount
	);
	event RemovedAuthorityAddresses (
		bytes32 indexed id,
		address[] removed,
		uint64 ownerCount
	);

	modifier onlyOwner() {
		require(idMap[msg.sender].id == ownerID);
		require(!idMap[msg.sender].restricted);
		_;
	}

	modifier onlyAuthority() {
		bytes32 _id = idMap[msg.sender].id;
		require(_id != 0);
		require(!idMap[msg.sender].restricted);
		if (_id != ownerID) {
			require(authorityData[_id].signatures[msg.sig]);
			require(authorityData[idMap[msg.sender].id].approvedUntil >= now);
		}
		_;
	}

	modifier onlySelfAuthority(bytes32 _id) {
		require (_id != 0);
		if (idMap[msg.sender].id != ownerID) {
			require(idMap[msg.sender].id == _id);
		}
		_;
	}

	constructor(address[] _owners, uint64 _threshold) public {
		require(_owners.length >= _threshold);
		require(_owners.length > 0);
		ownerID = keccak256(abi.encodePacked(address(this)));
		Authority storage a = authorityData[ownerID];
		for (uint256 i = 0; i < _owners.length; i++) {
			idMap[_owners[i]].id = ownerID;
		}
		a.addressCount = uint64(_owners.length);
		a.multiSigThreshold = _threshold;
		a.approvedUntil = 18446744073709551615;
		emit NewAuthority(ownerID, _threshold, a.approvedUntil);
		emit NewAuthorityAddresses(ownerID, _owners, a.addressCount);
	}

	function _checkMultiSig() internal onlyAuthority returns (bool) {
		bytes32 _callHash = keccak256(msg.data);
		bytes32 _id = idMap[msg.sender].id;
		Authority storage a = authorityData[_id];
		for (uint256 i = 0; i < a.multiSigAuth[_callHash].length; i++) {
			require(a.multiSigAuth[_callHash][i] != msg.sender);
		}
		if (a.multiSigAuth[_callHash].length + 1 >= a.multiSigThreshold) {
			delete a.multiSigAuth[_callHash];
			emit MultiSigCallApproved(_id, msg.sig, _callHash, msg.sender);
			return true;
		}
		a.multiSigAuth[_callHash].push(msg.sender);
		emit MultiSigCall(
			_id, 
			msg.sig,
			_callHash,
			msg.sender,
			a.multiSigAuth[_callHash].length,
			a.multiSigThreshold
		);
		return false;
	}

	function addAuthority(
		bytes32 _id,
		address[] _owners,
		bytes4[] _signatures,
		uint64 _approvedUntil,
		uint64 _threshold
	)
		external
		onlyOwner
		returns (bool)
	{
		if (!_checkMultiSig()) {
			return false;
		}
		require (_owners.length >= _threshold);
		require (_owners.length > 0);
		Authority storage a = authorityData[_id];
		require(a.addressCount == 0);
		require(_id != 0);
		for (uint256 i = 0; i < _owners.length; i++) {
			require(idMap[_owners[i]].id == 0);
			idMap[_owners[i]].id = _id;
		}
		for (i = 0; i < _signatures.length; i++) {
			a.signatures[_signatures[i]] = true;
		}
		a.approvedUntil = _approvedUntil;
		a.addressCount = uint64(_owners.length);
		a.multiSigThreshold = _threshold;
		emit NewAuthority(_id, _threshold, _approvedUntil);
		emit NewAuthorityAddresses(_id, _owners, a.addressCount);
		return true;
	}

	function setApprovedUntil(bytes32 _id, uint64 _approvedUntil) external onlyOwner returns (bool) {
		if (!_checkMultiSig()) {
			return false;
		}
		require(authorityData[_id].addressCount > 0);
		authorityData[_id].approvedUntil = _approvedUntil;
		emit ApprovedUntilSet(_id, _approvedUntil);
		return true;
	}

	function addPermittedSignatures(bytes32 _id, bytes4[] _signatures) external onlyOwner returns (bool) {
		if (!_checkMultiSig()) {
			return false;
		}
		Authority storage a = authorityData[_id];
		require(a.addressCount > 0);
		for (uint256 i = 0; i < _signatures.length; i++) {
			a.signatures[_signatures[i]] = true;
		}
		emit NewAuthorityPermissions(_id, _signatures);
		return true;
	}

	function removedPermittedSignatures(bytes32 _id, bytes4[] _signatures) external onlyOwner returns (bool) {
		if (!_checkMultiSig()) {
			return false;
		}
		Authority storage a = authorityData[_id];
		require(a.addressCount > 0);
		for (uint256 i = 0; i < _signatures.length; i++) {
			a.signatures[_signatures[i]] = false;
		}
		emit RemovedAuthorityPermissions(_id, _signatures);
		return true;
	}

	function setMultiSigThreshold(bytes32 _id, uint64 _threshold) external onlySelfAuthority(_id) returns (bool) {
		if (!_checkMultiSig()) {
			return false;
		}
		Authority storage a = authorityData[idMap[msg.sender].id];
		require(a.addressCount >= _threshold);
		a.multiSigThreshold = _threshold;
		emit ThresholdSet(_id, _threshold);
		return true;
	}

	function addAuthorityAddresses(bytes32 _id, address[] _owners) external onlySelfAuthority(_id) returns (bool) {
		if (!_checkMultiSig()) {
			return false;
		}
		Authority storage a = authorityData[_id];
		require(a.addressCount > 0);
		for (uint256 i = 0; i < _owners.length; i++) {
			require(idMap[_owners[i]].id == 0);
			idMap[_owners[i]].id = _id;
		}
		a.addressCount = a.addressCount.add(uint64(_owners.length));
		emit NewAuthorityAddresses(_id, _owners, a.addressCount);
		return true;
	}

	function removeAuthorityAddresses(bytes32 _id, address[] _owners) external onlySelfAuthority(_id)  returns (bool) {
		if (!_checkMultiSig()) {
			return false;
		}
		Authority storage a = authorityData[_id];
		for (uint256 i = 0; i < _owners.length; i++) {
			require(idMap[_owners[i]].id == _id);
			require(!idMap[_owners[i]].restricted);
			idMap[_owners[i]].restricted = true;
		}
		a.addressCount = a.addressCount.sub(uint64(_owners.length));
		require (a.addressCount >= a.multiSigThreshold);
		require (a.addressCount > 0);
		emit RemovedAuthorityAddresses(_id, _owners, a.addressCount);
		return true;
	}


}
