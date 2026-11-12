'use strict';

class ShadowAdapter {
  constructor(options) {
    this.recorder = options && options.recorder;
    if (!this.recorder) throw new Error('shadow recorder is required');
  }

  handle(routeId, payload) {
    const data = payload || {};
    switch (routeId) {
      case 'contacts.list':
      case 'users.search':
      case 'chats.list':
      case 'moments.list':
      case 'moments.notices':
        return { status: 'read-observed', routeId };
      case 'friends.request':
        return this.recorder.friendRequested(data.friendship);
      case 'friends.respond':
        return data.accept
          ? this.recorder.friendAccepted(data.friendship)
          : this.recorder.friendRejected(data.friendship);
      case 'friends.remove':
        return this.recorder.friendRemoved(data.actorId, data.targetId, data.eventId);
      case 'friends.clear':
        return (data.targets || []).map((targetId) =>
          this.recorder.friendRemoved(data.actorId, targetId, data.eventId + ':' + targetId));
      case 'chats.hide':
        return this.recorder.chatHidden(data.chatId, data.ownerId, data.eventId);
      case 'chats.messages.create':
        return (data.recipientIds || []).map((ownerId) =>
          this.recorder.chatMessageShown(data.chatId, ownerId, data.messageId));
      case 'chats.unread':
        return this.recorder.chatUnread(data.chatId, data.ownerId, data.unread, data.eventId);
      case 'chats.pin':
        return this.recorder.chatPinned(data.chatId, data.ownerId, data.pinned, data.eventId);
      case 'chats.kick':
        return this.recorder.chatMemberRemoved(data.chatId, data.userId, 'kick');
      case 'chats.leave':
        return this.recorder.chatMemberRemoved(data.chatId, data.userId, 'leave');
      case 'chats.dismiss':
        return this.recorder.groupDismissed(data.chatId, data.eventId);
      case 'moments.publish':
        return this.recorder.momentPublished(data.moment);
      case 'moments.comment':
        return this.recorder.momentCommented(data.momentId, data.comment);
      case 'moments.like':
        return data.liked === false
          ? this.recorder.momentUnliked(data.momentId, data.userId, data.at, data.eventId)
          : this.recorder.momentLiked(data.momentId, data.userId, data.at, data.eventId);
      case 'moments.comment-like':
        return data.liked === false
          ? this.recorder.momentCommentUnliked(
            data.momentId, data.commentId, data.userId, data.at, data.eventId)
          : this.recorder.momentCommentLiked(
            data.momentId, data.commentId, data.userId, data.at, data.eventId);
      case 'transfers.claim':
        return this.recorder.transferClaimed(data.transfer, data.userId);
      default:
        return { status: 'unmapped', routeId };
    }
  }
}

module.exports = { ShadowAdapter };
