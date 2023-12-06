// SPDX-License-Identifier: GNU AGPLv3
pragma solidity ^0.8.0;

library MerkleTreeLib {
    struct Node {
        bool created;
        address left;
        address right;
        uint256 value;
        bytes32 hashNode;
    }

    function isEmpty(Node memory node) internal pure returns (bool) {
        return
            node.left == address(0) &&
            node.right == address(0) &&
            node.value == 0 &&
            node.hashNode == bytes32(0);
    }

    struct Tree {
        mapping(address => Node) nodes;
        address root;
    }

    function newAccount(
        Tree storage tree,
        address addr,
        uint256 value
    ) internal {
        Node storage node = tree.nodes[addr];
        require(addr != address(0));
        require(!node.created);
        require(value != 0);

        node.created = true;
        node.value = value;
        node.hashNode = keccak256(abi.encodePacked(addr, value));
        require(node.hashNode << 160 != 0);
    }

    function newNode(
        Tree storage tree,
        address parent,
        address left,
        address right
    ) internal {
        Node storage parentNode = tree.nodes[parent];
        Node storage leftNode = tree.nodes[left];
        Node storage rightNode = tree.nodes[right];
        require(parent != address(0));
        require(!parentNode.created);
        require(leftNode.created && rightNode.created);
        require(leftNode.hashNode <= rightNode.hashNode);

        // Notice that internal nodes have value 0.
        parentNode.created = true;
        parentNode.left = left;
        parentNode.right = right;
        parentNode.hashNode = keccak256(abi.encode(leftNode.hashNode, rightNode.hashNode));
        require(parentNode.hashNode << 160 != 0);
    }

    function setRoot(Tree storage tree, address addr) internal {
        require(tree.nodes[addr].created);
        tree.root = addr;
    }

    function isWellFormed(Tree storage tree, address addr) internal view returns (bool) {
        Node storage node = tree.nodes[addr];

        if (!node.created) return isEmpty(node);

        // Trick to make the verification discriminate between internal nodes and leaves.
        // Safe because it will prompt a revert if this condition is not respected.
        if (node.hashNode << 160 == 0) return false;

        if (node.left == address(0) && node.right == address(0)) {
            return
                node.value != 0 && node.hashNode == keccak256(abi.encodePacked(addr, node.value));
        } else {
            // Well-formed nodes have exactly 0 or 2 children.
            if (node.left == address(0) || node.right == address(0)) return false;
            Node storage left = tree.nodes[node.left];
            Node storage right = tree.nodes[node.right];
            // Well-formed nodes should have its children pair-sorted.
            bool sorted = left.hashNode <= right.hashNode;
            return
                left.created &&
                right.created &&
                node.value == 0 &&
                sorted &&
                node.hashNode == keccak256(abi.encode(left.hashNode, right.hashNode));
        }
    }

    function getRoot(Tree storage tree) internal view returns (address) {
        return tree.root;
    }

    function getCreated(Tree storage tree, address addr) internal view returns (bool) {
        return tree.nodes[addr].created;
    }

    function getLeft(Tree storage tree, address addr) internal view returns (address) {
        return tree.nodes[addr].left;
    }

    function getRight(Tree storage tree, address addr) internal view returns (address) {
        return tree.nodes[addr].right;
    }

    function getValue(Tree storage tree, address addr) internal view returns (uint256) {
        return tree.nodes[addr].value;
    }

    function getHash(Tree storage tree, address addr) internal view returns (bytes32) {
        return tree.nodes[addr].hashNode;
    }
}
