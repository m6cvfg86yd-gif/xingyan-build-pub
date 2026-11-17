import SwiftUI
import UIKit

struct NativeStaticItem: Identifiable, Equatable {
    let id: String
    let signature: String
}

private final class NativeStaticHostCell: UICollectionViewCell {
    private var host: UIHostingController<AnyView>?
    private var hostedID = ""

    override func prepareForReuse() {
        super.prepareForReuse()
    }

    func setRootView(_ rootView: AnyView, id: String) {
        if host == nil {
            let next = UIHostingController(rootView: rootView)
            next.view.backgroundColor = .clear
            contentView.addSubview(next.view)
            host = next
        } else if hostedID != id {
            host?.rootView = rootView
        } else {
            host?.rootView = rootView
        }
        hostedID = id
        host?.view.frame = contentView.bounds
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        host?.view.frame = contentView.bounds
    }
}

final class NativeStaticListController {
    fileprivate var scrollToIDHandler: ((String, UICollectionView.ScrollPosition, Bool) -> Bool)?
    fileprivate var scrollToBottomHandler: ((Bool) -> Bool)?

    @discardableResult
    func scrollToID(_ id: String,
                    at position: UICollectionView.ScrollPosition = .centeredVertically,
                    animated: Bool = true) -> Bool {
        scrollToIDHandler?(id, position, animated) ?? false
    }

    @discardableResult
    func scrollToBottom(animated: Bool = false) -> Bool {
        scrollToBottomHandler?(animated) ?? false
    }

    fileprivate func clear() {
        scrollToIDHandler = nil
        scrollToBottomHandler = nil
    }
}

struct NativeStaticList<Item: Identifiable & Equatable, Row: View>: UIViewControllerRepresentable
where Item.ID: Hashable {
    let items: [Item]
    let controller: NativeStaticListController?
    let onScrollViewReady: ((UIScrollView) -> Void)?
    let onScrollStateChange: ((Bool) -> Void)?
    let onScrollOffset: ((CGFloat) -> Void)?
    let onSizeChange: (() -> Void)?
    let signature: (Item) -> String
    @ViewBuilder let row: (Item) -> Row

    init(items: [Item],
         controller: NativeStaticListController? = nil,
         onScrollViewReady: ((UIScrollView) -> Void)? = nil,
         onScrollStateChange: ((Bool) -> Void)? = nil,
         onScrollOffset: ((CGFloat) -> Void)? = nil,
         onSizeChange: (() -> Void)? = nil,
         signature: @escaping (Item) -> String,
         @ViewBuilder row: @escaping (Item) -> Row) {
        self.items = items
        self.controller = controller
        self.onScrollViewReady = onScrollViewReady
        self.onScrollStateChange = onScrollStateChange
        self.onScrollOffset = onScrollOffset
        self.onSizeChange = onSizeChange
        self.signature = signature
        self.row = row
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(controller: controller,
                    onScrollViewReady: onScrollViewReady,
                    onScrollStateChange: onScrollStateChange,
                    onScrollOffset: onScrollOffset,
                    onSizeChange: onSizeChange,
                    signature: signature,
                    row: row)
    }

    func makeUIViewController(context: Context) -> UICollectionViewController {
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .vertical
        layout.minimumLineSpacing = 0
        layout.minimumInteritemSpacing = 0
        layout.estimatedItemSize = .zero

        let controller = UICollectionViewController(collectionViewLayout: layout)
        controller.view.backgroundColor = .clear
        let collection = controller.collectionView!
        collection.backgroundColor = .clear
        collection.alwaysBounceVertical = true
        collection.alwaysBounceHorizontal = false
        collection.isDirectionalLockEnabled = true
        collection.showsVerticalScrollIndicator = true
        collection.contentInsetAdjustmentBehavior = .never
        collection.keyboardDismissMode = .interactive
        collection.delaysContentTouches = false
        collection.canCancelContentTouches = true
        collection.scrollsToTop = true
        collection.isPrefetchingEnabled = true
        collection.delegate = context.coordinator

        let registration = UICollectionView.CellRegistration<NativeStaticHostCell, Item.ID> {
            [weak coordinator = context.coordinator] cell, _, id in
            guard let coordinator,
                  let item = coordinator.lookup[id],
                  let rootView = coordinator.rootView(for: item) else { return }
            cell.setRootView(rootView, id: String(describing: id))
            cell.backgroundConfiguration = .clear()
            cell.backgroundColor = .clear
            cell.clipsToBounds = true
        }

        let dataSource = UICollectionViewDiffableDataSource<Int, Item.ID>(
            collectionView: collection
        ) { collectionView, indexPath, id in
            collectionView.dequeueConfiguredReusableCell(
                using: registration,
                for: indexPath,
                item: id
            )
        }
        context.coordinator.dataSource = dataSource
        context.coordinator.collection = collection
        context.coordinator.attachController()
        context.coordinator.attachScroll(collection)
        context.coordinator.apply(items, animated: false)
        return controller
    }

    func updateUIViewController(_ controller: UICollectionViewController,
                                context: Context) {
        context.coordinator.row = row
        context.coordinator.signature = signature
        context.coordinator.onScrollViewReady = onScrollViewReady
        context.coordinator.onScrollStateChange = onScrollStateChange
        context.coordinator.onScrollOffset = onScrollOffset
        context.coordinator.onSizeChange = onSizeChange
        context.coordinator.attachController()
        if let collection = controller.collectionView {
            context.coordinator.attachScroll(collection)
        }
        context.coordinator.apply(items, animated: false)
    }

    final class Coordinator: NSObject, UICollectionViewDelegateFlowLayout {
        var lookup: [Item.ID: Item] = [:]
        var row: (Item) -> Row
        var signature: (Item) -> String
        weak var collection: UICollectionView?
        var dataSource: UICollectionViewDiffableDataSource<Int, Item.ID>?
        let controller: NativeStaticListController?
        var onScrollViewReady: ((UIScrollView) -> Void)?
        var onScrollStateChange: ((Bool) -> Void)?
        var onScrollOffset: ((CGFloat) -> Void)?
        var onSizeChange: (() -> Void)?
        private var sizeObservation: NSKeyValueObservation?
        private var lastScrollState: Bool?
        private var order: [Item.ID] = []
        private var signatures: [Item.ID: String] = [:]
        private var heights: [Item.ID: CGFloat] = [:]
        private var width: CGFloat = 0
        private var pending: [Item]?
        private var applyGeneration = 0
        private var sizeChangeScheduled = false

        init(controller: NativeStaticListController?,
             onScrollViewReady: ((UIScrollView) -> Void)?,
             onScrollStateChange: ((Bool) -> Void)?,
             onScrollOffset: ((CGFloat) -> Void)?,
             onSizeChange: (() -> Void)?,
             signature: @escaping (Item) -> String,
             row: @escaping (Item) -> Row) {
            self.controller = controller
            self.onScrollViewReady = onScrollViewReady
            self.onScrollStateChange = onScrollStateChange
            self.onScrollOffset = onScrollOffset
            self.onSizeChange = onSizeChange
            self.signature = signature
            self.row = row
            super.init()
        }

        deinit {
            sizeObservation?.invalidate()
        }

        func attachScroll(_ scrollView: UIScrollView) {
            onScrollViewReady?(scrollView)
            if sizeObservation == nil {
                sizeObservation = scrollView.observe(\.contentSize, options: [.new]) {
                    [weak self] _, _ in
                    guard let self else { return }
                    guard !self.sizeChangeScheduled else { return }
                    self.sizeChangeScheduled = true
                    DispatchQueue.main.async { [weak self] in
                        guard let self else { return }
                        self.sizeChangeScheduled = false
                        self.onSizeChange?()
                    }
                }
            }
            publishScrollState(
                scrollView.isDragging || scrollView.isDecelerating || scrollView.isTracking
            )
        }

        func publishScrollState(_ active: Bool) {
            guard lastScrollState != active else { return }
            lastScrollState = active
            onScrollStateChange?(active)
        }

        func attachController() {
            guard let controller else { return }
            controller.scrollToIDHandler = { [weak self] id, position, animated in
                guard let self, let collection = self.collection else { return false }
                self.flush()
                collection.layoutIfNeeded()
                guard let index = self.order.firstIndex(where: {
                    String(describing: $0) == id
                }) else { return false }
                collection.scrollToItem(
                    at: IndexPath(item: index, section: 0),
                    at: position,
                    animated: animated
                )
                return true
            }
            controller.scrollToBottomHandler = { [weak self] animated in
                guard let self, let collection = self.collection else { return false }
                self.flush()
                collection.layoutIfNeeded()
                let minimumY = -collection.adjustedContentInset.top
                let maximumY = max(
                    minimumY,
                    collection.contentSize.height - collection.bounds.height
                        + collection.adjustedContentInset.bottom
                )
                collection.setContentOffset(CGPoint(x: 0, y: maximumY), animated: animated)
                return true
            }
        }

        func apply(_ next: [Item], animated: Bool) {
            guard let collection, let dataSource else { return }
            let nextOrder = next.map(\.id)
            // The first item is often a permanent history sentinel. Detect a
            // prepend from any existing row that moved down, rather than only
            // checking item zero, otherwise the atomic offset compensation is
            // skipped and a loaded page can flash in one frame later.
            let nextPositions = Dictionary(
                uniqueKeysWithValues: nextOrder.enumerated().map { ($1, $0) }
            )
            let isPrepending = order.enumerated().contains { oldPosition, id in
                guard let nextPosition = nextPositions[id] else { return false }
                return nextPosition > oldPosition
            }
            let nextSignatures = Dictionary(uniqueKeysWithValues: next.map {
                ($0.id, signature($0))
            })
            if !order.isEmpty && (collection.isDragging || collection.isDecelerating) {
                let known = Set(order)
                let commonOrder = nextOrder.filter { known.contains($0) }
                if commonOrder != order {
                    pending = next
                    return
                }
            }
            if nextOrder == order && nextSignatures == signatures { return }
            let nextLookup = Dictionary(uniqueKeysWithValues: next.map { ($0.id, $0) })
            let changed = nextOrder.filter { signatures[$0] != nextSignatures[$0] }
            for id in changed { heights[id] = nil }
            let widthChanged = collection.bounds.width > 1
                && abs(collection.bounds.width - width) > 0.5
            if widthChanged {
                width = collection.bounds.width
                heights.removeAll(keepingCapacity: true)
            }
            lookup = nextLookup
            signatures = nextSignatures
            order = nextOrder
            pending = nil
            premeasure(nextOrder)
            let previousOffset = collection.contentOffset
            let prependAnchor: (id: Item.ID, delta: CGFloat)?
            if isPrepending,
               let indexPath = collection.indexPathsForVisibleItems.min(by: {
                   $0.item < $1.item
               }),
               let id = dataSource.itemIdentifier(for: indexPath),
               let attributes = collection.collectionViewLayout
                   .layoutAttributesForItem(at: indexPath) {
                prependAnchor = (
                    id,
                    attributes.frame.minY - collection.contentOffset.y
                )
            } else {
                prependAnchor = nil
            }
            applyGeneration += 1
            let generation = applyGeneration
            var snapshot = NSDiffableDataSourceSnapshot<Int, Item.ID>()
            snapshot.appendSections([0])
            snapshot.appendItems(nextOrder)
            if !changed.isEmpty { snapshot.reloadItems(changed) }
            if widthChanged {
                collection.collectionViewLayout.invalidateLayout()
            }
            dataSource.apply(snapshot, animatingDifferences: animated) {
                guard generation == self.applyGeneration,
                      self.collection === collection else { return }
                collection.layoutIfNeeded()
                if isPrepending {
                    if let anchor = prependAnchor,
                       let indexPath = dataSource.indexPath(for: anchor.id),
                       let attributes = collection.collectionViewLayout
                           .layoutAttributesForItem(at: indexPath) {
                        collection.setContentOffset(
                            CGPoint(
                                x: previousOffset.x,
                                y: attributes.frame.minY - anchor.delta
                            ),
                            animated: false
                        )
                        ChatScrollHandle.shared.clearPendingPrepend()
                        return
                    }
                    _ = ChatScrollHandle.shared.compensatePendingPrepend()
                    return
                }
                guard !collection.isTracking,
                      !collection.isDragging,
                      !collection.isDecelerating else { return }
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
            let resolved = dataSource?.itemIdentifier(for: indexPath)
            let fallback = indexPath.item < order.count ? order[indexPath.item] : nil
            guard let id = resolved ?? fallback, let item = lookup[id] else { return .zero }
            let width = max(1, collectionView.bounds.width)
            let height = heights[id] ?? measuredHeight(item, width: width)
            heights[id] = height
            return CGSize(width: width, height: height)
        }

        func scrollViewDidEndDragging(_ scrollView: UIScrollView,
                                      willDecelerate decelerate: Bool) {
            publishScrollState(decelerate)
            if !decelerate { flush() }
        }

        func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
            ChatScrollHandle.shared.noteUserMotion()
            publishScrollState(true)
        }

        func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
            publishScrollState(false)
            flush()
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            if scrollView.isDragging || scrollView.isTracking || scrollView.isDecelerating {
                ChatScrollHandle.shared.noteUserMotion()
            }
            onScrollOffset?(scrollView.contentOffset.y)
            publishScrollState(
                scrollView.isDragging || scrollView.isTracking || scrollView.isDecelerating
            )
        }

        private func premeasure(_ ids: [Item.ID]) {
            let measured = collection?.bounds.width ?? 0
            let width = measured > 1 ? measured : UIScreen.main.bounds.width
            guard width > 1 else { return }
            for id in ids where heights[id] == nil {
                guard let item = lookup[id] else { continue }
                heights[id] = measuredHeight(item, width: width)
            }
        }

        private func measuredHeight(_ item: Item, width: CGFloat) -> CGFloat {
            let host = UIHostingController(
                rootView: AnyView(row(item).frame(width: width))
            )
            host.view.backgroundColor = .clear
            host.view.frame = CGRect(x: 0, y: 0, width: width, height: 240)
            host.view.setNeedsLayout()
            host.view.layoutIfNeeded()
            let size = host.sizeThatFits(
                in: CGSize(width: width, height: .greatestFiniteMagnitude)
            )
            return max(1, ceil(size.height.isFinite ? size.height : 240))
        }

        func rootView(for item: Item) -> AnyView? {
            AnyView(
                row(item)
                    .frame(maxWidth: .infinity, alignment: .top)
            )
        }

        private func flush() {
            guard let pending else { return }
            self.pending = nil
            apply(pending, animated: false)
        }
    }
}
