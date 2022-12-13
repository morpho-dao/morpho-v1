using MerkleTree as M

methods {
    claim(address, uint256, bytes32[]) envfree
}

rule noClaimAgain(address _account, uint256 _claimable, bytes32[] _proof) {
    env e;  uint256 claimed;

    require (claimed <= _claimable);

    claim(_account, _claimable, _proof);

    claim@withrevert(_account, claimed, _proof);

    assert lastReverted;
}

rule treeExists() {
    env e; M.Tree t;
    require M.isValidTree(e, t);

    assert M.treeToAddress(e, t) == 1;
}
