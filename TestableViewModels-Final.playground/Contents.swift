import Foundation
import Combine
import SwiftUI

//MARK: - Domain

protocol Action {}

struct Product: Identifiable {
    
    let id: String
    let name: String
}

struct Statement: Identifiable {
    
    let id: String
    let productId: Product.ID
    let amount: Decimal
}

//MARK: - Model

struct Model {
    
    let action: PassthroughSubject<Action, Never>
    
    let products: CurrentValueSubject<[Product], Never>
    let statements: CurrentValueSubject<[Statement], Never>
}

enum ModelAction {
    
    enum ProductActions {
        
        enum Block {
            
            struct Request: Action {
                
                let productId: Product.ID
            }
            
            struct Resonse: Action {
                
                let productId: Product.ID
                let result: Result<Bool, Error>
            }
        }
    }
}

//MARK: - ViewModel

protocol ProductsVeiwModelContentService {
    
    var content: AnyPublisher<([Product], [Statement]), Never> { get }
    var amountFormatter: NumberFormatter { get }
    var blockProductResponse: AnyPublisher<(Product.ID, Result<Bool, Error>), Never> { get }
    
    func reduce(products: [Product], statements: [Statement], formatter: NumberFormatter, action: (ProductsViewModel.ItemViewModel.ID) -> (() -> Void)) -> [ProductsViewModel.ItemViewModel]
    func blockProductRequest(productId: Product.ID)
    func reduce(state: inout ProductsViewModel.State, result: Result<Bool, Error>, productId: Product.ID)
}

struct ProductsContentServiceAdapter: ProductsVeiwModelContentService {
    
    let content: AnyPublisher<([Product], [Statement]), Never>
    let amountFormatter: NumberFormatter
    let blockProductResponse: AnyPublisher<(Product.ID, Result<Bool, Error>), Never>
    
    let modelAction: PassthroughSubject<Action, Never>
    
    init(content: AnyPublisher<([Product], [Statement]), Never>, amountFormatter: NumberFormatter, blockProductResponse: AnyPublisher<(Product.ID, Result<Bool, Error>), Never>, modelAction: PassthroughSubject<Action, Never>) {
        
        self.content = content
        self.amountFormatter = amountFormatter
        self.blockProductResponse = blockProductResponse
        self.modelAction = modelAction
    }
    
    init(model: Model) {
        
        self.init(
            content: model.products.combineLatest(model.statements).eraseToAnyPublisher(),
            amountFormatter: .amount,
            blockProductResponse: model.action.compactMap({ $0 as? ModelAction.ProductActions.Block.Resonse}).map({($0.productId, $0.result)}).eraseToAnyPublisher(),
            modelAction: model.action)
    }

    func reduce(products: [Product], statements: [Statement], formatter: NumberFormatter, action: (ProductsViewModel.ItemViewModel.ID) -> (() -> Void)) -> [ProductsViewModel.ItemViewModel] {
        
        products.map { product in
            
            if let statement = statements.first(where: { $0.productId == product.id }) {
                
                let amount = formatter.string(for: statement.amount) ?? "\(statement.amount)"
                return .init(id: product.id, name: product.name, amount: amount, action: action(product.id))
                
            } else {
                
                return .init(id: product.id, name: product.name, amount: "UNKNOWN", action: action(product.id))
            }
        }
    }
    
    func blockProductRequest(productId: Product.ID) {
        
        modelAction.send(ModelAction.ProductActions.Block.Request(productId: productId))
    }
    
    func reduce(state: inout ProductsViewModel.State, result: Result<Bool, Error>, productId: Product.ID) {
        
        switch result {
        case let .success(successed):
            guard successed, case let .items(items) = state else {
                return
            }
            
            let updatedItems = items.filter { $0.id != productId }
            withAnimation {
                
                state = .items(updatedItems)
            }
            
        case let .failure(error):
            print("Failed blocking product : \(productId) with error: \(error.localizedDescription)")
        }
    }
}

final class ProductsViewModel_alt: ObservableObject {
    
    @Published private(set) var state: ProductsViewModel.State
    
    // it should be the responsibility of the caller/composition root to provide `dataService` adapted for the need of `ProductsViewModel`
    init(
        initialState: ProductsViewModel.State = .placeholders,
        dataService: AnyPublisher<[Item], Never>,
        select: @escaping (Item.ID) -> Void
        // + scheduler
    ) {
        self.state = initialState
        
        dataService
            .removeDuplicates()
            .map {
                $0.map { ProductsViewModel.ItemViewModel(item: $0, select: select) }
            }
            .map(ProductsViewModel.State.init)
        // replace with scheduler
            .receive(on: DispatchQueue.main)
            .assign(to: &$state)
    }
    
    struct Item: Identifiable, Equatable {
        
        let id: Product.ID
        let name: String
        let amount: String
    }
}
    
extension ProductsViewModel.ItemViewModel {
    
    init(
        item: ProductsViewModel_alt.Item,
        select: @escaping (ProductsViewModel_alt.Item.ID) -> Void
    ) {
        self.init(id: item.id, name: item.name, amount: item.amount, action: select)
    }
}

extension ProductsViewModel.State {
    
    init(items: [ProductsViewModel.ItemViewModel]) {
        
        if items.isEmpty {
            self = .placeholders
        } else {
            self = .items(items)
        }
    }
}
    
final class ProductsViewModel: ObservableObject {
    
    let action: PassthroughSubject<Action, Never> = .init()
    
    @Published var state: State
    
    private let contentService: ProductsVeiwModelContentService
    private var bindings = Set<AnyCancellable>()
    
    init(state: State, contentService: ProductsVeiwModelContentService) {
        
        self.state = state
        self.contentService = contentService
    }
    
    convenience init(contentService: ProductsVeiwModelContentService) {
        self.init(state: .placeholders, contentService: contentService)
        bind()
    }
    
    //TODO: remove after update code that creates ProductsViewModel
    convenience init(model: Model) {
        
        self.init(contentService: ProductsContentServiceAdapter(model: model))
    }
}

extension ProductsViewModel {
    
    func bind() {
        
        contentService.content
            .receive(on: DispatchQueue.main)
            .sink { [unowned self] products, statements in
                
                let items = contentService.reduce(products: products, statements: statements, formatter: contentService.amountFormatter) { [weak self] itemId in
                    
                    { self?.action.send(ProductsViewModelAction.ItemDidTapped(itemId: itemId)) }
                }
                withAnimation {
                    
                    state = .items(items)
                }
                
            }.store(in: &bindings)
        
        action
            .compactMap { $0 as? ProductsViewModelAction.ItemDidTapped }
            .map(\.itemId)
            .receive(on: DispatchQueue.main)
            .sink { [unowned self] itemId in
                
                contentService.blockProductRequest(productId: itemId)
                
            }.store(in: &bindings)
        
        contentService.blockProductResponse
            .receive(on: DispatchQueue.main)
            .sink { [unowned self] productId, result in
                
                contentService.reduce(state: &state, result: result, productId: productId)
                
            }.store(in: &bindings)
    }
}

extension ProductsViewModel {
    
    enum State {
        
        case placeholders
        case items([ItemViewModel])
    }
    
    struct ItemViewModel: Identifiable {
        
        let id: Product.ID
        let name: String
        let amount: String
        let action: (Product.ID) -> Void
    }
}

enum ProductsViewModelAction {
    
    struct ItemDidTapped: Action {
        
        let itemId: ProductsViewModel.ItemViewModel.ID
    }
}

//MARK: - Extensions

extension NumberFormatter {
    
    static let amount: NumberFormatter = {
        
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 2
        
        return formatter
    }()
}
