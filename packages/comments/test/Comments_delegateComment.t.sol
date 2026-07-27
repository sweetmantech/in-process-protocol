// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";

import {CommentsImpl} from "../src/CommentsImpl.sol";
import {Comments} from "../src/proxy/Comments.sol";
import {IComments} from "../src/interfaces/IComments.sol";
import {Mock1155} from "./mocks/Mock1155.sol";
import {MockDelegateCommenter} from "./mocks/MockDelegateCommenter.sol";

contract Comments_mintAndCommentTest is Test {
    Mock1155 mock1155;
    CommentsImpl comments;

    address zoraRecipient = makeAddr("zoraRecipient");
    address commentsAdmin = makeAddr("commentsAdmin");
    address commenter = makeAddr("commenter");
    address tokenAdmin = makeAddr("tokenAdmin");
    address backfiller = makeAddr("backfiller");
    address referrer = makeAddr("referrer");

    uint256 tokenId1 = 1;

    address constant protocolRewards = 0x7777777F279eba3d3Ad8F4E708545291A6fDBA8B;
    MockDelegateCommenter mockDelegateCommenter;

    function setUp() public {
        vm.createSelectFork("zora_sepolia", 14562731);

        CommentsImpl commentsImpl = new CommentsImpl(0.000001 ether, protocolRewards, zoraRecipient);

        comments = CommentsImpl(payable(address(new Comments(address(commentsImpl)))));

        mockDelegateCommenter = new MockDelegateCommenter(address(comments));

        address[] memory delegateCommenters = new address[](1);
        delegateCommenters[0] = address(mockDelegateCommenter);
        comments.initialize({defaultAdmin: commentsAdmin, backfiller: backfiller, delegateCommenters: delegateCommenters});

        mock1155 = new Mock1155();

        mock1155.createToken(tokenId1, tokenAdmin);
    }

    function _expectedCommentIdentifier(
        address _commenter,
        address contractAddress,
        uint256 tokenId
    ) internal view returns (IComments.CommentIdentifier memory) {
        return IComments.CommentIdentifier({commenter: _commenter, contractAddress: contractAddress, tokenId: tokenId, nonce: comments.nextNonce()});
    }

    function testCanDelegateCommentWithoutPayment() public {
        uint256 quantityToMint = 1;

        address contractAddress = address(mock1155);
        uint256 tokenId = tokenId1;

        IComments.CommentIdentifier memory emptyReplyTo;

        IComments.CommentIdentifier memory expectedCommentIdentifier = _expectedCommentIdentifier(commenter, contractAddress, tokenId);

        bytes32 expectedCommentId = comments.hashCommentIdentifier(expectedCommentIdentifier);
        bytes32 expectedReplyToId = bytes32(0);

        vm.expectEmit(true, true, true, true);
        emit IComments.Commented(
            expectedCommentId,
            _expectedCommentIdentifier(commenter, contractAddress, tokenId),
            expectedReplyToId,
            emptyReplyTo,
            0,
            "test",
            block.timestamp,
            referrer
        );
        vm.prank(commenter);
        mockDelegateCommenter.mintAndComment({
            quantity: quantityToMint,
            collection: address(mock1155),
            tokenId: tokenId1,
            comment: "test",
            referrer: referrer
        });
    }

    function testDelegateCommentRevertsWhenPaymentSent() public {
        uint256 quantityToMint = 1;
        uint256 mintFee = 0.000111 ether;

        vm.deal(commenter, mintFee * quantityToMint + 0.000001 ether);

        vm.prank(commenter);
        vm.expectRevert(abi.encodeWithSelector(IComments.CommentPaymentNotAllowed.selector, 0.000001 ether));
        mockDelegateCommenter.mintAndCommentWithSpark{value: 0.000001 ether + mintFee * quantityToMint}({
            quantity: quantityToMint,
            collection: address(mock1155),
            tokenId: tokenId1,
            comment: "test",
            referrer: referrer,
            sparksQuantity: 1
        });
    }

    function test_delegateComment_revertsWhenNotOwnerOrCreator() public {
        address notOwner = makeAddr("notOwner");
        vm.prank(notOwner);
        vm.expectRevert(IComments.NotTokenHolderOrAdmin.selector);
        mockDelegateCommenter.forwardComment(address(mock1155), tokenId1, "test");
    }
}
