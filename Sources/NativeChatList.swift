import SwiftUI
import UIKit

struct NativeChatList<Item: Identifiable & Equatable, Row: View>: UIViewControllerRepresentable
where Item.ID: Hashable {
    let items: [Item]
    let height: (Item) -> CGFloat
    let nativeRow: ((Item) -> NativeChatRowConfiguration?)?
    let onScrollStateChange: (Bool) -> Void
    let onZoneChange: (Int) -> Void
    let onApproachingEnd: () -> Void
    let onRefresh: () -> Void
    let allowInsertionDuringScroll: Bool
    @ViewBuilder let row: (Item) -> Row

    func makeCoordinator() -> Coordinator {
        Coordinator(onScrollStateChange: onScrollStateChange,
                    onZoneChange: onZoneChange,
                    onApproachingEnd: onApproachingEnd,
                    onRefresh: onRefresh,
                    allowInsertionDuringScroll: allowInsertionDuringScroll,
                    height: height,
                    nativeRow: nativeRow,
                    row: row)
    }

    func makeUIViewController(context: Context) -> UICollectionViewController {
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .vertical
        layout.minimumLineSpacing = 0
        layout.minimumInteritemSpacing = 0
        layout.sectionInset = .zero
        layout.estimatedItemSize = .zero

        let controller = UICollectionViewController(collectionViewLayout: layout)
        controller.view.backgroundColor = .clear
        let collection = controller.collectionView!
        collection.backgroundColor = .clear
        collection.alwaysBounceVertical = true
        collection.alwaysBounceHorizontal = false
        collection.showsVerticalScrollIndicator = false
        collection.contentInsetAdjustmentBehavior = .never
        collection.keyboardDismissMode = .interactive
        collection.delaysContentTouches = false
        collection.canCancelContentTouches = true
        collection.scrollsToTop = true
        collection.allowsFocus = true
        collection.remembersLastFocusedIndexPath = true
        collection.isPrefetchingEnabled = true
        collection.allowsSelection = true
        collection.allowsMultipleSelection = false
        if #available(iOS 26.0, *) {
            collection.topEdgeEffect.isHidden = true
            collection.bottomEdgeEffect.isHidden = true
        }
        collection.delegate = context.coordinator

        let registration = UICollectionView.CellRegistration<UICollectionViewCell, Item.ID> {
            [weak coordinator = context.coordinator] cell, _, id in
            guard let coordinator, let entry = coordinator.lookup[id] else { return }
            cell.contentConfiguration = UIHostingConfiguration {
                coordinator.row(entry)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .margins(.all, 0)
            .background(.clear)
            cell.backgroundConfiguration = .clear()
            cell.clipsToBounds = true
        }
        let nativeRegistration = UICollectionView.CellRegistration<NativeChatRowCell, Item.ID> {
            cell, _, _ in
            cell.backgroundConfiguration = .clear()
            cell.backgroundColor = .clear
        }

        let dataSource = UICollectionViewDiffableDataSource<Int, Item.ID>(
            collectionView: collection
        ) { collectionView, indexPath, id in
            if let entry = context.coordinator.lookup[id],
               let configuration = context.coordinator.nativeRow?(entry) {
                let cell = collectionView.dequeueConfiguredReusableCell(
                    using: nativeRegistration,
                    for: indexPath,
                    item: id
                )
                cell.configure(configuration)
                return cell
            }
            return collectionView.dequeueConfiguredReusableCell(
                using: registration,
                for: indexPath,
                item: id
            )
        }
        context.coordinator.dataSource = dataSource
        context.coordinator.collection = collection
        context.coordinator.apply(items, animated: false)

        let refresh = UIRefreshControl()
        refresh.addTarget(context.coordinator,
                          action: #selector(Coordinator.refreshPulled(_:)),
                          for: .valueChanged)
        collection.refreshControl = refresh
        return controller
    }

    func updateUIViewController(_ controller: UICollectionViewController,
                                context: Context) {
        context.coordinator.row = row
        context.coordinator.height = height
        context.coordinator.nativeRow = nativeRow
        context.coordinator.onScrollStateChange = onScrollStateChange
        context.coordinator.onZoneChange = onZoneChange
        context.coordinator.onApproachingEnd = onApproachingEnd
        context.coordinator.onRefresh = onRefresh
        context.coordinator.allowInsertionDuringScroll = allowInsertionDuringScroll
        context.coordinator.apply(items, animated: false)
    }

    final class Coordinator: NSObject, UICollectionViewDelegateFlowLayout {
        var lookup: [Item.ID: Item] = [:]
        var row: (Item) -> Row
        var height: (Item) -> CGFloat
        var nativeRow: ((Item) -> NativeChatRowConfiguration?)?
        var onScrollStateChange: (Bool) -> Void
        var onZoneChange: (Int) -> Void
        var onApproachingEnd: () -> Void
        var onRefresh: () -> Void
        var allowInsertionDuringScroll: Bool
        weak var collection: UICollectionView?
        var dataSource: UICollectionViewDiffableDataSource<Int, Item.ID>?
        private var order: [Item.ID] = []
        private var lastZone = -1
        private var pendingZone = 0
        private var zoneFlushScheduled = false
        private var lastScrollActive = false
        private var pendingItems: [Item]?
        private var applyGeneration = 0
        private var endRequestInFlight = false
        private var appliedItemCount = 0
        private var layoutObservers: [NSObjectProtocol] = []

        init(onScrollStateChange: @escaping (Bool) -> Void,
             onZoneChange: @escaping (Int) -> Void,
             onApproachingEnd: @escaping () -> Void,
             onRefresh: @escaping () -> Void,
             allowInsertionDuringScroll: Bool,
             height: @escaping (Item) -> CGFloat,
             nativeRow: ((Item) -> NativeChatRowConfiguration?)?,
             row: @escaping (Item) -> Row) {
            self.onScrollStateChange = onScrollStateChange
            self.onZoneChange = onZoneChange
            self.onApproachingEnd = onApproachingEnd
            self.onRefresh = onRefresh
            self.allowInsertionDuringScroll = allowInsertionDuringScroll
            self.height = height
            self.nativeRow = nativeRow
            self.row = row
            super.init()
            let center = NotificationCenter.default
            for name in [UIContentSizeCategory.didChangeNotification,
                         Notification.Name.chrisUIPrefsChanged] {
                layoutObservers.append(center.addObserver(forName: name,
                                                          object: nil,
                                                          queue: .main) { [weak self] _ in
                    self?.refreshMetrics()
                })
            }
        }

        deinit {
            let center = NotificationCenter.default
            layoutObservers.forEach { center.removeObserver($0) }
        }

        func apply(_ next: [Item], animated: Bool) {
            guard let dataSource, let collection else { return }
            /*
             * Diffable apply 会异步重排 cell。滚动过程中继续换快照，系统会把当前
             * 视口推进到错误位置，表现就是会话页突然往下掉。用户手指还在屏幕上时
             * 只记下最新数据，等滚动结束再一次性合并。
             */
            let isPureAppend = next.count > order.count
                && next.prefix(order.count).allSatisfy { lookup[$0.id] == $0 }
            let isStableInsertion = allowInsertionDuringScroll
                && isInsertionOnly(next)
            if !order.isEmpty,
               !isPureAppend,
               !isStableInsertion,
               collection.isDragging || collection.isDecelerating {
                pendingItems = next
                return
            }
            let nextLookup = Dictionary(uniqueKeysWithValues: next.map { ($0.id, $0) })
            let nextOrder = next.map(\.id)
            if nextOrder == order && next.allSatisfy({ lookup[$0.id] == $0 }) {
                pendingItems = nil
                return
            }
            let reload = next.compactMap { item -> Item.ID? in
                guard let old = lookup[item.id] else { return nil }
                return old == item ? nil : item.id
            }
            let previousOffset = collection.contentOffset
            applyGeneration += 1
            let generation = applyGeneration
            lookup = nextLookup

            var snapshot = NSDiffableDataSourceSnapshot<Int, Item.ID>()
            snapshot.appendSections([0])
            snapshot.appendItems(nextOrder, toSection: 0)
            if !reload.isEmpty {
                snapshot.reloadItems(reload)
            }
            order = nextOrder
            if appliedItemCount != nextOrder.count {
                appliedItemCount = nextOrder.count
                endRequestInFlight = false
            }
            pendingItems = nil
            dataSource.apply(snapshot, animatingDifferences: animated) {
                guard generation == self.applyGeneration,
                      self.collection === collection,
                      !collection.isTracking,
                      !collection.isDragging,
                      !collection.isDecelerating else { return }
                collection.layoutIfNeeded()
                let minimumY = -collection.adjustedContentInset.top
                let maximumY = max(
                    minimumY,
                    collection.contentSize.height - collection.bounds.height
                        + collection.adjustedContentInset.bottom
                )
                var target = previousOffset
                target.y = min(max(target.y, minimumY), maximumY)
                collection.setContentOffset(target, animated: false)
            }
        }

        func collectionView(_ collectionView: UICollectionView,
                            layout collectionViewLayout: UICollectionViewLayout,
                            sizeForItemAt indexPath: IndexPath) -> CGSize {
            let resolvedId = dataSource?.itemIdentifier(for: indexPath)
            let fallbackId = indexPath.item >= 0 && indexPath.item < order.count
                ? order[indexPath.item] : nil
            guard let id = resolvedId ?? fallbackId,
                  let item = lookup[id] else { return .zero }
            let width = max(0,
                            collectionView.bounds.width
                            - collectionView.adjustedContentInset.left
                            - collectionView.adjustedContentInset.right)
            return CGSize(width: width, height: max(1, height(item)))
        }

        @objc func refreshPulled(_ sender: UIRefreshControl) {
            onRefresh()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
                sender.endRefreshing()
            }
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            publishScrollState(scrollView.isDragging
                               || scrollView.isTracking
                               || scrollView.isDecelerating)
            let y = scrollView.contentOffset.y
            let remaining = scrollView.contentSize.height
                - scrollView.bounds.height
                - y
                + scrollView.adjustedContentInset.bottom
            if !endRequestInFlight,
               !order.isEmpty,
               (scrollView.isDragging || scrollView.isDecelerating),
               remaining < 900 {
                endRequestInFlight = true
                DispatchQueue.main.async { [weak self] in
                    self?.onApproachingEnd()
                }
            }
            let zone: Int
            if y < 1 { zone = 0 }
            else if y <= 8 { zone = 1 }
            else if y <= 14 { zone = 2 }
            else { zone = 3 }
            guard zone != lastZone else { return }
            lastZone = zone
            pendingZone = zone
            guard !zoneFlushScheduled else { return }
            zoneFlushScheduled = true
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.zoneFlushScheduled = false
                self.onZoneChange(self.pendingZone)
            }
        }

        func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
            publishScrollState(true)
            /* 让正在等待的异步布局完成回调失效，不能把用户的拖动位置写回旧值。 */
            applyGeneration += 1
            NotificationCenter.default.post(name: .chrisRowSwipe, object: nil)
        }

        func scrollViewDidEndDragging(_ scrollView: UIScrollView,
                                      willDecelerate decelerate: Bool) {
            if decelerate {
                publishScrollState(true)
            } else {
                publishScrollState(false)
                flushPendingItems()
            }
        }

        func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
            publishScrollState(false)
            flushPendingItems()
        }

        func collectionView(_ collectionView: UICollectionView,
                            didSelectItemAt indexPath: IndexPath) {
            collectionView.deselectItem(at: indexPath, animated: false)
            guard let id = dataSource?.itemIdentifier(for: indexPath),
                  let entry = lookup[id],
                  let configuration = nativeRow?(entry) else { return }
            configuration.onOpen()
        }

        func collectionView(_ collectionView: UICollectionView,
                            canEditItemAt indexPath: IndexPath) -> Bool {
            guard let id = dataSource?.itemIdentifier(for: indexPath),
                  let entry = lookup[id] else { return false }
            return nativeRow?(entry) != nil
        }

        func collectionView(
            _ collectionView: UICollectionView,
            leadingSwipeActionsConfigurationForItemAt indexPath: IndexPath
        ) -> UISwipeActionsConfiguration? {
            guard let id = dataSource?.itemIdentifier(for: indexPath),
                  let entry = lookup[id],
                  let configuration = nativeRow?(entry) else { return nil }
            let pin = UIContextualAction(
                style: .normal,
                title: configuration.isPinned ? Tr("取消置顶") : Tr("置顶")
            ) { _, _, completion in
                configuration.onPin(!configuration.isPinned)
                completion(true)
            }
            pin.image = UIImage(systemName: configuration.isPinned
                                ? "pin.slash.fill" : "pin.fill")
            pin.backgroundColor = UIColor(hex: 0x0A84FF)
            let swipe = UISwipeActionsConfiguration(actions: [pin])
            swipe.performsFirstActionWithFullSwipe = false
            return swipe
        }

        func collectionView(
            _ collectionView: UICollectionView,
            trailingSwipeActionsConfigurationForItemAt indexPath: IndexPath
        ) -> UISwipeActionsConfiguration? {
            guard let id = dataSource?.itemIdentifier(for: indexPath),
                  let entry = lookup[id],
                  let configuration = nativeRow?(entry) else { return nil }
            let unread = UIContextualAction(
                style: .normal,
                title: Tr("标为未读")
            ) { _, _, completion in
                configuration.onUnread()
                completion(true)
            }
            unread.image = UIImage(systemName: "envelope.badge.fill")
            unread.backgroundColor = UIColor(hex: 0x28986C)

            let hide = UIContextualAction(
                style: .normal,
                title: Tr("不显示")
            ) { _, _, completion in
                configuration.onHide()
                completion(true)
            }
            hide.image = UIImage(systemName: "eye.slash.fill")
            hide.backgroundColor = UIColor(hex: 0x7B8087)

            let delete = UIContextualAction(
                style: .destructive,
                title: Tr("删除")
            ) { _, _, completion in
                configuration.onDelete()
                completion(true)
            }
            delete.image = UIImage(systemName: "trash.fill")
            delete.backgroundColor = .systemRed

            // UIKit lays trailing actions out from the screen edge toward the row.
            // Delete stays closest to the edge; unread is the innermost action.
            let swipe = UISwipeActionsConfiguration(actions: [delete, hide, unread])
            swipe.performsFirstActionWithFullSwipe = false
            return swipe
        }

        private func publishScrollState(_ active: Bool) {
            guard active != lastScrollActive else { return }
            lastScrollActive = active
            DispatchQueue.main.async { [weak self] in
                self?.onScrollStateChange(active)
            }
        }

        private func refreshMetrics() {
            guard let collection, let dataSource else { return }
            NativeChatRowMetrics.invalidateScaleCache()
            let previousOffset = collection.contentOffset
            collection.collectionViewLayout.invalidateLayout()
            var snapshot = dataSource.snapshot()
            guard !snapshot.itemIdentifiers.isEmpty else { return }
            snapshot.reloadItems(snapshot.itemIdentifiers)
            dataSource.apply(snapshot, animatingDifferences: false) { [weak collection] in
                guard let collection,
                      !collection.isTracking,
                      !collection.isDragging,
                      !collection.isDecelerating else { return }
                collection.layoutIfNeeded()
                let minimumY = -collection.adjustedContentInset.top
                let maximumY = max(
                    minimumY,
                    collection.contentSize.height - collection.bounds.height
                        + collection.adjustedContentInset.bottom
                )
                var target = previousOffset
                target.y = min(max(target.y, minimumY), maximumY)
                collection.setContentOffset(target, animated: false)
            }
        }

        private func flushPendingItems() {
            guard let pendingItems else { return }
            self.pendingItems = nil
            apply(pendingItems, animated: false)
        }

        private func isInsertionOnly(_ next: [Item]) -> Bool {
            guard next.count > order.count else { return false }
            var cursor = 0
            for id in order {
                while cursor < next.count, next[cursor].id != id {
                    cursor += 1
                }
                guard cursor < next.count, lookup[id] == next[cursor] else {
                    return false
                }
                cursor += 1
            }
            return true
        }
    }
}
