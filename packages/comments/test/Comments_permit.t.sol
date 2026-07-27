// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";

import {CommentsImpl} from "../src/CommentsImpl.sol";
import {Comments} from "../src/proxy/Comments.sol";
import {IComments} from "../src/interfaces/IComments.sol";
import {Mock1155} from "./mocks/Mock1155.sol";
import {IProtocolRewards} from "@zoralabs/protocol-rewards/src/interfaces/IProtocolRewards.sol";
import {ProtocolRewards} from "./mocks/ProtocolRewards.sol";
import {CommentsTestBase} from "./CommentsTestBase.sol";
import {UnorderedNoncesUpgradeable} from "@zoralabs/shared-contracts/utils/UnorderedNoncesUpgradeable.sol";
import {MockMultiOwnable} from "./Comments_smartWallet.t.sol";

contract CommentsPermitTest is CommentsTestBase {
    function testPermitComment() public {
        IComments.PermitComment memory permitComment = _createPermitComment(collectorWithToken, "test comment");
        bytes memory signature = _signPermitComment(permitComment, collectorWithTokenPrivateKey);

        IComments.CommentIdentifier memory expectedCommentIdentifier = _expectedCommentIdentifier(
            permitComment.contractAddress,
            permitComment.tokenId,
            permitComment.commenter
        );

        _setupTokenAndSparks(permitComment);

        // any account can execute the permit comment on behalf of the collectorWithToken.
        address executor = makeAddr("executor");

        vm.expectEmit(true, true, true, true);
        emit IComments.Commented(
            comments.hashCommentIdentifier(expectedCommentIdentifier),
            expectedCommentIdentifier,
            bytes32(0),
            permitComment.replyTo,
            0,
            permitComment.text,
            block.timestamp,
            permitComment.referrer
        );

        _executePermitComment(executor, permitComment, signature);

        _assertCommentExists(expectedCommentIdentifier);
    }

    function testPermitComment_NonceUsedTwice() public {
        IComments.PermitComment memory permitComment = _createPermitComment(collectorWithToken, "test comment");
        bytes memory signature = _signPermitComment(permitComment, collectorWithTokenPrivateKey);

        _setupTokenAndSparks(permitComment);

        // First comment should succeed
        _executePermitComment(collectorWithToken, permitComment, signature);

        // Second comment with same nonce should fail
        vm.expectRevert(abi.encodeWithSelector(UnorderedNoncesUpgradeable.InvalidAccountNonce.selector, collectorWithToken, permitComment.nonce));
        _executePermitComment(collectorWithToken, permitComment, signature);
    }

    function testPermitComment_DeadlineExpired() public {
        IComments.PermitComment memory permitComment = _createPermitComment(collectorWithToken, "test comment");
        bytes memory signature = _signPermitComment(permitComment, collectorWithTokenPrivateKey);

        _setupTokenAndSparks(permitComment);

        // Warp time to after the deadline
        vm.warp(permitComment.deadline + 1);

        address executor = makeAddr("executor");
        vm.expectRevert(abi.encodeWithSelector(IComments.ERC2612ExpiredSignature.selector, permitComment.deadline));
        _executePermitComment(executor, permitComment, signature);
    }

    function testPermitComment_CommenterDoesntMatchSigner() public {
        address wrongSigner;
        uint256 wrongSignerPrivateKey;
        (wrongSigner, wrongSignerPrivateKey) = makeAddrAndKey("wrongSigner");

        IComments.PermitComment memory permitComment = _createPermitComment(collectorWithToken, "test comment");
        bytes memory wrongSignature = _signPermitComment(permitComment, wrongSignerPrivateKey);

        _setupTokenAndSparks(permitComment);

        vm.expectRevert(IComments.InvalidSignature.selector);
        _executePermitComment(collectorWithToken, permitComment, wrongSignature);
    }

    function testPermitComment_ZeroSparks_Collector() public {
        IComments.PermitComment memory permitComment = _createPermitComment(collectorWithToken, "test comment");
        bytes memory signature = _signPermitComment(permitComment, collectorWithTokenPrivateKey);

        _setupTokenAndSparks(permitComment);

        IComments.CommentIdentifier memory expectedCommentIdentifier = _expectedCommentIdentifier(
            permitComment.contractAddress,
            permitComment.tokenId,
            permitComment.commenter
        );

        vm.prank(collectorWithToken);
        comments.permitComment(permitComment, signature);

        _assertCommentExists(expectedCommentIdentifier);
    }

    function testPermitComment_ZeroSparks_Creator() public {
        IComments.PermitComment memory permitComment = _createPermitComment(tokenAdmin, "test comment");
        bytes memory signature = _signPermitComment(permitComment, tokenAdminPrivateKey);

        _setupTokenAndSparks(permitComment);

        bytes32 expectedNonce = comments.nextNonce();

        // any account can execute the permit comment on behalf of the tokenAdmin,
        // it should be executed with 0 sparks
        vm.prank(makeAddr("random account"));
        comments.permitComment(permitComment, signature);

        IComments.CommentIdentifier memory expectedCommentIdentifier = IComments.CommentIdentifier({
            commenter: tokenAdmin,
            contractAddress: address(mock1155),
            tokenId: tokenId1,
            nonce: expectedNonce
        });
        _assertCommentExists(expectedCommentIdentifier);
    }

    function testPermitCommentRevertsWhenPaymentSent() public {
        IComments.PermitComment memory permitComment = _createPermitComment(collectorWithToken, "test comment");
        bytes memory signature = _signPermitComment(permitComment, collectorWithTokenPrivateKey);

        _setupTokenAndSparks(permitComment);

        vm.expectRevert(abi.encodeWithSelector(IComments.CommentPaymentNotAllowed.selector, SPARKS_VALUE));
        vm.prank(collectorWithToken);
        comments.permitComment{value: SPARKS_VALUE}(permitComment, signature);
    }

    function testPermitComment_Not1155Holder() public {
        IComments.PermitComment memory permitComment = _createPermitComment(collectorWithToken, "test comment");
        bytes memory signature = _signPermitComment(permitComment, collectorWithTokenPrivateKey);

        address executor = makeAddr("executor");
        vm.expectRevert(IComments.NotTokenHolderOrAdmin.selector);
        _executePermitComment(executor, permitComment, signature);
    }

    function testPermitComment_SmartWalletOwner() public {
        // Test scenario:
        // We want to enable a smart wallet owner to comment when the smart wallet owns the token.
        // - The smart wallet owns the 1155 token
        // - privy account is an owner of the smart wallet
        // - privy account is the one that signs the message
        // - The comment is attributed to privy account (the smart wallet owner)
        // We create a permit where:
        // - commenter is privy account (smart wallet owner)
        // - commenterSmartWallet is the smart wallet address
        // - Privy account signs the message
        // This should be a valid scenario, allowing a smart wallet owner to comment using a token owned by the smart wallet.
        (address privyAccount, uint256 privyPrivateKey) = makeAddrAndKey("privy");

        address smartWallet = address(new MockMultiOwnable(privyAccount));

        mock1155.mint(smartWallet, tokenId1, 1, "");

        IComments.PermitComment memory permitComment = IComments.PermitComment({
            // comment will be attributed to the smart wallet - it should be the one that
            // has the signature checked against it.
            commenter: privyAccount,
            contractAddress: address(mock1155),
            tokenId: tokenId1,
            replyTo: IComments.CommentIdentifier({commenter: address(0), contractAddress: address(0), tokenId: 0, nonce: bytes32(0)}),
            text: "smart wallet comment",
            deadline: uint48(block.timestamp + 1000),
            nonce: bytes32(0),
            referrer: address(0),
            sourceChainId: uint32(100),
            destinationChainId: uint32(block.chainid),
            // collectorWithToken is the smart wallet owner - this is the account that actually owns the 1155 token.
            commenterSmartWallet: smartWallet
        });

        // sign the permit - but we have the another account (privy) sign for the smart wallet, since it is also an owner
        bytes memory signature = _signPermitComment(permitComment, privyPrivateKey);

        IComments.CommentIdentifier memory expectedCommentIdentifier = _expectedCommentIdentifier(
            permitComment.contractAddress,
            permitComment.tokenId,
            // privy account is the one that signs the message, but the smart wallet is the one that is commenting
            privyAccount
        );

        address executor = makeAddr("executor");
        _executePermitComment(executor, permitComment, signature);

        _assertCommentExists(expectedCommentIdentifier);
    }

    function testPermitSparkCommentDisabled() public {
        IComments.PermitSparkComment memory permitSparkComment = _postCommentAndCreatePermitSparkComment(sparker, 3);
        bytes memory signature = _signPermitSparkComment(permitSparkComment, sparkerPrivateKey);

        vm.expectRevert(IComments.SparkingDisabled.selector);
        _executePermitSparkComment(makeAddr("executor"), permitSparkComment, signature);
    }

    function testPermitCommentCrossChain() public {
        uint32 sourceChainId = 1; // Ethereum mainnet
        uint32 destinationChainId = uint32(block.chainid);

        IComments.PermitComment memory permitComment = _createPermitComment(collectorWithToken, "cross-chain comment");
        permitComment.sourceChainId = sourceChainId;
        permitComment.destinationChainId = destinationChainId;

        IComments.CommentIdentifier memory expectedCommentIdentifier = _expectedCommentIdentifier(
            permitComment.contractAddress,
            permitComment.tokenId,
            permitComment.commenter
        );

        bytes memory signature = _signPermitComment(permitComment, collectorWithTokenPrivateKey);

        _setupTokenAndSparks(permitComment);

        address executor = makeAddr("executor");

        vm.expectEmit(true, true, true, true);
        emit IComments.Commented(
            comments.hashCommentIdentifier(expectedCommentIdentifier),
            expectedCommentIdentifier,
            bytes32(0),
            permitComment.replyTo,
            0,
            permitComment.text,
            block.timestamp,
            permitComment.referrer
        );

        _executePermitComment(executor, permitComment, signature);

        _assertCommentExists(expectedCommentIdentifier);
    }

    function testPermitCommentCrossChainInvalidDestination() public {
        uint32 sourceChainId = 1; // Ethereum mainnet
        uint32 invalidDestinationChainId = 42; // Some other chain ID

        IComments.PermitComment memory permitComment = _createPermitComment(collectorWithToken, "invalid cross-chain comment");
        permitComment.sourceChainId = sourceChainId;
        permitComment.destinationChainId = invalidDestinationChainId;

        bytes memory signature = _signPermitComment(permitComment, collectorWithTokenPrivateKey);

        _setupTokenAndSparks(permitComment);

        address executor = makeAddr("executor");

        vm.expectRevert(abi.encodeWithSelector(IComments.IncorrectDestinationChain.selector, invalidDestinationChainId));
        _executePermitComment(executor, permitComment, signature);
    }

    function testPermitSparkCommentCrossChainDisabled() public {
        uint32 sourceChainId = 1;
        uint32 destinationChainId = uint32(block.chainid);

        IComments.PermitSparkComment memory permitSparkComment = _postCommentAndCreatePermitSparkComment(sparker, 3);
        permitSparkComment.sourceChainId = sourceChainId;
        permitSparkComment.destinationChainId = destinationChainId;

        bytes memory signature = _signPermitSparkComment(permitSparkComment, sparkerPrivateKey);

        vm.expectRevert(IComments.SparkingDisabled.selector);
        _executePermitSparkComment(makeAddr("executor"), permitSparkComment, signature);
    }

    function testPermitSparkCommentCrossChainInvalidDestinationDisabled() public {
        uint32 sourceChainId = 1;
        uint32 invalidDestinationChainId = 42;

        IComments.PermitSparkComment memory permitSparkComment = _postCommentAndCreatePermitSparkComment(sparker, 3);
        permitSparkComment.sourceChainId = sourceChainId;
        permitSparkComment.destinationChainId = invalidDestinationChainId;

        bytes memory signature = _signPermitSparkComment(permitSparkComment, sparkerPrivateKey);

        vm.expectRevert(IComments.SparkingDisabled.selector);
        _executePermitSparkComment(makeAddr("executor"), permitSparkComment, signature);
    }

    function _postCommentAndCreatePermitSparkComment(address _sparker, uint64 sparksQuantity) internal returns (IComments.PermitSparkComment memory) {
        IComments.CommentIdentifier memory emptyReplyTo;
        address commenter = makeAddr("commenter_b");
        IComments.CommentIdentifier memory commentIdentifier = _mockComment(commenter, emptyReplyTo);

        return _createPermitSparkComment(commentIdentifier, _sparker, sparksQuantity, uint32(block.chainid), uint32(block.chainid));
    }

    // Helper functions
    function _createPermitSparkComment(
        IComments.CommentIdentifier memory commentIdentifier,
        address _sparker,
        uint64 sparksQuantity,
        uint32 sourceChainId,
        uint32 destinationChainId
    ) internal returns (IComments.PermitSparkComment memory) {
        return
            IComments.PermitSparkComment({
                comment: commentIdentifier,
                sparker: _sparker,
                sparksQuantity: sparksQuantity,
                deadline: block.timestamp + 100,
                nonce: bytes32("1"),
                referrer: makeAddr("referrer"),
                sourceChainId: sourceChainId,
                destinationChainId: destinationChainId
            });
    }

    function _signPermitSparkComment(IComments.PermitSparkComment memory permitSparkComment, uint256 privateKey) internal view returns (bytes memory) {
        bytes32 digest = comments.hashPermitSparkComment(permitSparkComment);
        return _sign(privateKey, digest);
    }

    function _executePermitSparkComment(address executor, IComments.PermitSparkComment memory permitSparkComment, bytes memory signature) internal {
        vm.prank(executor);
        comments.permitSparkComment(permitSparkComment, signature);
    }

    // Helper functions
    function _createPermitComment(address commenter, string memory text) internal returns (IComments.PermitComment memory) {
        return
            IComments.PermitComment({
                contractAddress: address(mock1155),
                tokenId: tokenId1,
                commenter: commenter,
                replyTo: emptyCommentIdentifier,
                text: text,
                deadline: block.timestamp + 100,
                nonce: bytes32("1"),
                referrer: makeAddr("referrer"),
                sourceChainId: uint32(block.chainid),
                destinationChainId: uint32(block.chainid),
                commenterSmartWallet: address(0)
            });
    }

    function _setupTokenAndSparks(IComments.PermitComment memory permitComment) internal {
        mock1155.mint(permitComment.commenter, permitComment.tokenId, 1, "");
    }

    function _executePermitComment(address executor, IComments.PermitComment memory permitComment, bytes memory signature) internal {
        vm.prank(executor);
        comments.permitComment(permitComment, signature);
    }

    function _assertCommentExists(IComments.CommentIdentifier memory commentIdentifier) internal view {
        (, bool exists) = comments.hashAndCheckCommentExists(commentIdentifier);
        assertTrue(exists);
    }

    function _signPermitComment(IComments.PermitComment memory permitComment, uint256 privateKey) internal view returns (bytes memory signature) {
        bytes32 digest = comments.hashPermitComment(permitComment);
        signature = _sign(privateKey, digest);
    }

    function _sign(uint256 privateKey, bytes32 digest) internal pure returns (bytes memory signature) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);
        return abi.encodePacked(r, s, v);
    }
}
