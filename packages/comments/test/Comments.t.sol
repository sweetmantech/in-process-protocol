// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";

import {IComments} from "../src/interfaces/IComments.sol";
import {Mock1155} from "./mocks/Mock1155.sol";
import {CommentsTestBase} from "./CommentsTestBase.sol";
import {Mock1155NoCreatorRewardRecipient} from "./mocks/Mock1155NoCreatorRewardRecipient.sol";
import {Mock1155NoOwner} from "./mocks/Mock1155NoOwner.sol";
import {CommentsImpl} from "../src/CommentsImpl.sol";
import {Comments} from "../src/proxy/Comments.sol";

contract CommentsTest is CommentsTestBase {
    function _setupCommenterWithToken(address commenter) internal {
        vm.startPrank(commenter);
        mock1155.mint(commenter, tokenId1, 1, "");
        vm.stopPrank();
    }

    function _createCommentIdentifier(address commenter, bytes32 nonce) internal view returns (IComments.CommentIdentifier memory) {
        return IComments.CommentIdentifier({commenter: commenter, contractAddress: address(mock1155), tokenId: tokenId1, nonce: nonce});
    }

    function testCommentContractName() public view {
        assertEq(comments.contractName(), "In Process Comments");
    }

    function testCommentWhenCollectorHasTokenShouldEmitCommented() public {
        _setupCommenterWithToken(collectorWithToken);

        address contractAddress = address(mock1155);
        uint256 tokenId = tokenId1;
        address commenter = collectorWithToken;

        IComments.CommentIdentifier memory expectedCommentIdentifier = _expectedCommentIdentifier(contractAddress, tokenId, commenter);

        IComments.CommentIdentifier memory replyTo;

        vm.expectEmit(true, true, true, true);
        emit IComments.Commented(
            comments.hashCommentIdentifier(expectedCommentIdentifier),
            expectedCommentIdentifier,
            0,
            replyTo,
            0,
            "test comment",
            block.timestamp,
            address(0)
        );
        vm.prank(collectorWithToken);
        comments.comment(collectorWithToken, contractAddress, tokenId, "test comment", replyTo, address(0), address(0));

        vm.assertEq(protocolRewards.balanceOf(collectorWithToken), 0);
        vm.assertEq(protocolRewards.balanceOf(zoraRecipient), 0);
        vm.assertEq(protocolRewards.balanceOf(tokenAdmin), 0);
    }

    function testCommentBackfillBatchAddCommentShouldEmitCommented() public {
        IComments.CommentIdentifier[] memory commentIdentifiers = new IComments.CommentIdentifier[](2);

        commentIdentifiers[0] = IComments.CommentIdentifier({
            commenter: makeAddr("commenter1"),
            contractAddress: address(mock1155),
            tokenId: tokenId1,
            nonce: 0
        });

        commentIdentifiers[1] = IComments.CommentIdentifier({
            commenter: makeAddr("commenter2"),
            contractAddress: address(mock1155),
            tokenId: tokenId2,
            nonce: bytes32("1")
        });

        string[] memory texts = new string[](2);
        texts[0] = "test comment 1";
        texts[1] = "test comment 2";

        uint256[] memory timestamps = new uint256[](2);

        timestamps[0] = block.timestamp;
        timestamps[1] = block.timestamp + 100;

        bytes32[] memory originalTransactionHashes = new bytes32[](2);
        originalTransactionHashes[0] = bytes32("1");
        originalTransactionHashes[1] = bytes32("2");

        vm.expectEmit(true, true, true, true);
        emit IComments.BackfilledComment({
            commentId: comments.hashCommentIdentifier(commentIdentifiers[0]),
            commentIdentifier: commentIdentifiers[0],
            text: texts[0],
            timestamp: timestamps[0],
            originalTransactionId: originalTransactionHashes[0]
        });
        vm.expectEmit(true, true, true, true);
        emit IComments.BackfilledComment({
            commentId: comments.hashCommentIdentifier(commentIdentifiers[1]),
            commentIdentifier: commentIdentifiers[1],
            text: texts[1],
            timestamp: timestamps[1],
            originalTransactionId: originalTransactionHashes[1]
        });

        vm.prank(commentsBackfiller);
        comments.backfillBatchAddComment(commentIdentifiers, texts, timestamps, originalTransactionHashes);
    }

    function testCommentBackfillBatchAddCommentShouldRevertIfDuplicate() public {
        IComments.CommentIdentifier[] memory commentIdentifiers = new IComments.CommentIdentifier[](2);

        commentIdentifiers[0] = IComments.CommentIdentifier({
            commenter: makeAddr("commenter1"),
            contractAddress: address(mock1155),
            tokenId: tokenId1,
            nonce: 0
        });

        commentIdentifiers[1] = IComments.CommentIdentifier({
            commenter: makeAddr("commenter2"),
            contractAddress: address(mock1155),
            tokenId: tokenId2,
            nonce: keccak256("1")
        });

        string[] memory texts = new string[](2);
        texts[0] = "test comment 1";
        texts[1] = "test comment 2";

        uint256[] memory timestamps = new uint256[](2);

        timestamps[0] = block.timestamp;
        timestamps[1] = block.timestamp + 100;

        bytes32[] memory originalTransactionHashes = new bytes32[](2);
        originalTransactionHashes[0] = bytes32("1");
        originalTransactionHashes[1] = bytes32("2");

        vm.prank(commentsBackfiller);
        comments.backfillBatchAddComment(commentIdentifiers, texts, timestamps, originalTransactionHashes);

        vm.expectRevert(abi.encodeWithSelector(IComments.DuplicateComment.selector, comments.hashCommentIdentifier(commentIdentifiers[0])));
        vm.prank(commentsBackfiller);
        comments.backfillBatchAddComment(commentIdentifiers, texts, timestamps, originalTransactionHashes);
    }

    function testCommentBackfillBatchAddCommentShouldRevertIfArrayLengthMismatch() public {
        IComments.CommentIdentifier[] memory commentIdentifiers = new IComments.CommentIdentifier[](2);
        commentIdentifiers[1] = commentIdentifiers[0];

        string[] memory texts = new string[](2);

        uint256[] memory timestamps = new uint256[](1);

        bytes32[] memory originalTransactionHashes = new bytes32[](2);

        vm.expectRevert(IComments.ArrayLengthMismatch.selector);
        vm.prank(commentsBackfiller);
        comments.backfillBatchAddComment(commentIdentifiers, texts, timestamps, originalTransactionHashes);
    }

    function testCommentSparkCommentWithZeroSparks() public {
        IComments.CommentIdentifier memory commentIdentifier = IComments.CommentIdentifier({
            commenter: collectorWithToken,
            contractAddress: address(mock1155),
            tokenId: tokenId1,
            nonce: bytes32(0)
        });
        vm.expectRevert(abi.encodeWithSignature("MustSendAtLeastOneSpark()"));
        comments.sparkComment(commentIdentifier, 0, address(0));
    }

    function testCommentSparkCommentRevertsWhenPaymentSent() public {
        IComments.CommentIdentifier memory replyTo;
        IComments.CommentIdentifier memory commentIdentifier = _mockComment(collectorWithToken, replyTo);

        vm.expectRevert(abi.encodeWithSelector(IComments.CommentPaymentNotAllowed.selector, SPARKS_VALUE));
        vm.prank(sparker);
        comments.sparkComment{value: SPARKS_VALUE}(commentIdentifier, 1, address(0));
    }

    function testCommentSparkCommentOwnComment() public {
        IComments.CommentIdentifier memory replyTo;
        IComments.CommentIdentifier memory commentIdentifier = _mockComment(collectorWithToken, replyTo);

        vm.expectRevert(abi.encodeWithSignature("CannotSparkOwnComment()"));
        vm.prank(collectorWithToken);
        comments.sparkComment(commentIdentifier, 1, address(0));
    }

    function testCommentSparkCommentDoesNotExist() public {
        IComments.CommentIdentifier memory commentIdentifier = IComments.CommentIdentifier({
            commenter: collectorWithToken,
            contractAddress: address(mock1155),
            tokenId: tokenId1,
            nonce: keccak256("123456")
        });
        vm.expectRevert(abi.encodeWithSignature("CommentDoesntExist()"));
        comments.sparkComment(commentIdentifier, 1, address(0));
    }

    function testCommentSparkCommentValid(uint256 sparksQuantity) public {
        vm.assume(sparksQuantity > 0 && sparksQuantity < 1_000_000_000_000_000);

        IComments.CommentIdentifier memory replyTo;
        IComments.CommentIdentifier memory commentIdentifier = _mockComment(collectorWithToken, replyTo);

        address commenter2 = makeAddr("commenter2");

        vm.expectEmit(true, true, true, true);
        emit IComments.SparkedComment(
            comments.hashCommentIdentifier(commentIdentifier),
            commentIdentifier,
            sparksQuantity,
            commenter2,
            block.timestamp,
            address(0)
        );
        vm.prank(commenter2);
        comments.sparkComment(commentIdentifier, sparksQuantity, address(0));

        vm.assertEq(protocolRewards.balanceOf(zoraRecipient), 0);
        vm.assertEq(protocolRewards.balanceOf(collectorWithToken), 0);
        vm.assertEq(comments.commentSparksQuantity(commentIdentifier), sparksQuantity);
    }

    function testCommentSparkCommentValidWithReferrer(uint256 sparksQuantity) public {
        vm.assume(sparksQuantity > 0 && sparksQuantity < 1_000_000_000_000_000);

        IComments.CommentIdentifier memory replyTo;
        IComments.CommentIdentifier memory commentIdentifier = _mockComment(collectorWithToken, replyTo);

        address commenter2 = makeAddr("commenter2");
        address referrer = makeAddr("referrer");

        vm.expectEmit(true, true, true, true);
        emit IComments.SparkedComment(
            comments.hashCommentIdentifier(commentIdentifier),
            commentIdentifier,
            sparksQuantity,
            commenter2,
            block.timestamp,
            referrer
        );
        vm.prank(commenter2);
        comments.sparkComment(commentIdentifier, sparksQuantity, referrer);

        vm.assertEq(protocolRewards.balanceOf(zoraRecipient), 0);
        vm.assertEq(protocolRewards.balanceOf(referrer), 0);
        vm.assertEq(protocolRewards.balanceOf(collectorWithToken), 0);
    }

    function testCommentHashAndValidateCommentExists() public {
        IComments.CommentIdentifier memory commentIdentifier = IComments.CommentIdentifier({
            commenter: collectorWithToken,
            contractAddress: address(mock1155),
            tokenId: tokenId1,
            nonce: keccak256("123456")
        });
        vm.expectRevert(abi.encodeWithSignature("CommentDoesntExist()"));
        comments.hashAndValidateCommentExists(commentIdentifier);
    }

    function postComment(
        address commenter,
        address contractAddress,
        uint256 tokenId,
        string memory content,
        IComments.CommentIdentifier memory replyTo
    ) internal returns (IComments.CommentIdentifier memory) {
        vm.prank(commenter);
        return comments.comment(commenter, contractAddress, tokenId, content, replyTo, address(0), address(0));
    }

    function testHashAndCheckCommentExists() public {
        address commenter = collectorWithToken;
        address contractAddress = address(mock1155);
        uint256 tokenId = tokenId1;

        (bytes32 commentId, bool exists) = comments.hashAndCheckCommentExists(_expectedCommentIdentifier(contractAddress, tokenId, commenter));
        assertFalse(exists);

        _setupCommenterWithToken(commenter);
        IComments.CommentIdentifier memory postedCommentIdentifier = postComment(commenter, contractAddress, tokenId, "test comment", emptyCommentIdentifier);

        (bytes32 newCommentId, bool newExists) = comments.hashAndCheckCommentExists(postedCommentIdentifier);
        assertTrue(newExists);
        assertEq(commentId, newCommentId);
        assertEq(comments.hashCommentIdentifier(postedCommentIdentifier), newCommentId);
    }

    function testReplyToNonExistentComment() public {
        address commenter = makeAddr("commenter");
        _setupCommenterWithToken(commenter);

        IComments.CommentIdentifier memory nonExistentReplyTo = IComments.CommentIdentifier({
            commenter: makeAddr("nonExistentCommenter"),
            contractAddress: address(mock1155),
            tokenId: tokenId1,
            nonce: keccak256("nonExistentNonce")
        });

        vm.expectRevert(IComments.CommentDoesntExist.selector);
        postComment(commenter, address(mock1155), tokenId1, "Replying to non-existent comment", nonExistentReplyTo);
    }

    function testReplyToCommentThatAddressDoesNotMatch() public {
        address originalCommenter = makeAddr("originalCommenter");
        address replier = makeAddr("replier");

        _setupCommenterWithToken(originalCommenter);
        _setupCommenterWithToken(replier);

        IComments.CommentIdentifier memory originalCommentIdentifier = postComment(
            originalCommenter,
            address(mock1155),
            tokenId1,
            "Original comment",
            emptyCommentIdentifier
        );

        address mismatchedAddress = makeAddr("xyz");

        vm.expectRevert(
            abi.encodeWithSelector(IComments.CommentAddressOrTokenIdsDoNotMatch.selector, mismatchedAddress, tokenId1, address(mock1155), tokenId1)
        );
        vm.prank(replier);
        comments.comment(replier, mismatchedAddress, tokenId1, "Reply to original comment", originalCommentIdentifier, address(0), address(0));

        uint256 mismatchedTokenId = 123;

        vm.expectRevert(
            abi.encodeWithSelector(IComments.CommentAddressOrTokenIdsDoNotMatch.selector, address(mock1155), mismatchedTokenId, address(mock1155), tokenId1)
        );
        vm.prank(replier);
        comments.comment(replier, address(mock1155), mismatchedTokenId, "Reply to original comment", originalCommentIdentifier, address(0), address(0));
    }

    function testReplyToExistingComment() public {
        address originalCommenter = makeAddr("originalCommenter");
        address replier = makeAddr("replier");

        _setupCommenterWithToken(originalCommenter);
        _setupCommenterWithToken(replier);

        IComments.CommentIdentifier memory originalCommentIdentifier = postComment(
            originalCommenter,
            address(mock1155),
            tokenId1,
            "Original comment",
            emptyCommentIdentifier
        );

        IComments.CommentIdentifier memory expectedReplyCommentIdentifier = _expectedCommentIdentifier(address(mock1155), tokenId1, replier);

        vm.expectEmit(true, true, true, true);
        emit IComments.Commented(
            comments.hashCommentIdentifier(expectedReplyCommentIdentifier),
            expectedReplyCommentIdentifier,
            comments.hashCommentIdentifier(originalCommentIdentifier),
            originalCommentIdentifier,
            0,
            "Reply to original comment",
            block.timestamp,
            address(0)
        );

        IComments.CommentIdentifier memory replyCommentIdentifier = postComment(
            replier,
            address(mock1155),
            tokenId1,
            "Reply to original comment",
            originalCommentIdentifier
        );

        assertEq(payable(address(comments)).balance, 0, "comments contract should have no balance");

        uint256 commenteeSparks = comments.commentSparksQuantity(originalCommentIdentifier);
        assertEq(commenteeSparks, 0, "commentee sparks should be 0");

        assertEq(protocolRewards.balanceOf(originalCommenter), 0, "rewards mismatch");

        (, bool exists) = comments.hashAndCheckCommentExists(replyCommentIdentifier);
        assertTrue(exists);
    }

    function testCommentMismatchedCommenter() public {
        address actualCommenter = makeAddr("actualCommenter");
        address mismatchedCommenter = makeAddr("mismatchedCommenter");

        _setupCommenterWithToken(actualCommenter);

        vm.expectRevert(abi.encodeWithSelector(IComments.CommenterMismatch.selector, mismatchedCommenter, actualCommenter));
        vm.prank(actualCommenter);
        comments.comment(mismatchedCommenter, address(mock1155), tokenId1, "Mismatched commenter", emptyCommentIdentifier, address(0), address(0));
    }

    function testRevertOnEmptyComment() public {
        address commenter = makeAddr("commenter");
        _setupCommenterWithToken(commenter);

        vm.expectRevert(IComments.EmptyComment.selector);
        postComment(commenter, address(mock1155), tokenId1, "", emptyCommentIdentifier);
    }

    function testRevertOnNotTokenHolderOrAdmin() public {
        address nonHolder = makeAddr("nonHolder");

        vm.expectRevert(IComments.NotTokenHolderOrAdmin.selector);
        postComment(nonHolder, address(mock1155), tokenId1, "Attempting to comment without holding token", emptyCommentIdentifier);
    }

    function testCommentRevertsWhenPaymentSent() public {
        address tokenHolder = makeAddr("tokenHolder");

        _setupCommenterWithToken(tokenHolder);

        vm.deal(tokenHolder, 1 ether);
        vm.prank(tokenHolder);
        vm.expectRevert(abi.encodeWithSelector(IComments.CommentPaymentNotAllowed.selector, 1 ether));
        comments.comment{value: 1 ether}(tokenHolder, address(mock1155), tokenId1, "test", emptyCommentIdentifier, address(0), address(0));
    }

    function testCommentSucceedsWithZeroValue() public {
        address tokenHolder = makeAddr("tokenHolder");

        _setupCommenterWithToken(tokenHolder);

        vm.prank(tokenHolder);
        comments.comment(tokenHolder, address(mock1155), tokenId1, "test", emptyCommentIdentifier, address(0), address(0));
    }

    function testCommentWithMock1155NoCreatorRewardRecipient() public {
        Mock1155NoCreatorRewardRecipient mock1155NoCreatorRewardRecipient = new Mock1155NoCreatorRewardRecipient();
        mock1155NoCreatorRewardRecipient.createToken(tokenId1, tokenAdmin);

        vm.startPrank(collectorWithToken);
        mock1155NoCreatorRewardRecipient.mint(collectorWithToken, tokenId1, 1, "");
        vm.stopPrank();

        address contractAddress = address(mock1155NoCreatorRewardRecipient);
        uint256 tokenId = tokenId1;

        IComments.CommentIdentifier memory replyTo;

        vm.prank(collectorWithToken);
        comments.comment(collectorWithToken, contractAddress, tokenId, "test comment", replyTo, address(0), address(0));
    }

    function testCommentWithMock1155NoOwner() public {
        Mock1155NoOwner mock1155NoOwner = new Mock1155NoOwner();
        mock1155NoOwner.createToken(tokenId1, tokenAdmin);

        vm.startPrank(collectorWithToken);
        mock1155NoOwner.mint(collectorWithToken, tokenId1, 1, "");
        vm.stopPrank();

        address contractAddress = address(mock1155NoOwner);
        uint256 tokenId = tokenId1;

        IComments.CommentIdentifier memory replyTo;

        vm.prank(collectorWithToken);
        comments.comment(collectorWithToken, contractAddress, tokenId, "test comment", replyTo, address(0), address(0));
    }

    function testImplementation() public view {
        assertEq(comments.implementation(), address(commentsImpl));
    }

    function testCommentsConstructorAddressZero() public {
        vm.expectRevert(abi.encodeWithSelector(IComments.AddressZero.selector));
        new CommentsImpl(SPARKS_VALUE, address(0), zoraRecipient);

        vm.expectRevert(abi.encodeWithSelector(IComments.AddressZero.selector));
        new CommentsImpl(SPARKS_VALUE, address(protocolRewards), address(0));
    }

    function testCommentsInitializeAddressZero() public {
        CommentsImpl implTest = new CommentsImpl(SPARKS_VALUE, address(protocolRewards), zoraRecipient);
        address[] memory delegateCommenters = new address[](0);

        CommentsImpl commentsProxyTest = CommentsImpl(payable(address(new Comments(address(implTest)))));
        vm.expectRevert(abi.encodeWithSelector(IComments.AddressZero.selector));
        commentsProxyTest.initialize({defaultAdmin: address(0), backfiller: commentsBackfiller, delegateCommenters: delegateCommenters});

        vm.expectRevert(abi.encodeWithSelector(IComments.AddressZero.selector));
        commentsProxyTest.initialize({defaultAdmin: commentsAdmin, backfiller: address(0), delegateCommenters: new address[](0)});
    }

    function testGrantRoleWithBackfillRole() public {
        address newBackfiller = makeAddr("newBackfiller");
        bytes32 BACKFILLER_ROLE = keccak256("BACKFILLER_ROLE");
        vm.prank(commentsAdmin);
        comments.grantRole(BACKFILLER_ROLE, newBackfiller);
        vm.assertEq(comments.hasRole(BACKFILLER_ROLE, newBackfiller), true);

        vm.prank(commentsAdmin);
        comments.revokeRole(BACKFILLER_ROLE, newBackfiller);
        vm.assertEq(comments.hasRole(BACKFILLER_ROLE, newBackfiller), false);

        address notAdmin = makeAddr("notAdmin");
        bytes32 no_role;
        vm.prank(notAdmin);
        vm.expectRevert(abi.encodeWithSignature("AccessControlUnauthorizedAccount(address,bytes32)", notAdmin, no_role));
        comments.grantRole(BACKFILLER_ROLE, newBackfiller);
    }
}
