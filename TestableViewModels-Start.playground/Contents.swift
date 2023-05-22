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

final class ProductsViewModel: ObservableObject {
    
    let action: PassthroughSubject<Action, Never> = .init()
    
    @Published var state: State
    
    private let model: Model
    private var bindings = Set<AnyCancellable>()
    
    init(state: State, model: Model) {
        
        self.state = state
        self.model = model
    }
    
    convenience init(model: Model) {
        
        self.init(state: .placeholders, model: model)
        bind()
    }
}

extension ProductsViewModel {
    
    private func bind() {
        
        model.products
            .combineLatest(model.statements)
            .receive(on: DispatchQueue.main)
            .sink { [unowned self] products, statements in
                
                let items = Self.reduce(products: products, statements: statements) { [weak self] itemId in
                    
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
                
                model.action.send(ModelAction.ProductActions.Block.Request(productId: itemId))
                
            }.store(in: &bindings)
        
        model.action
            .compactMap { $0 as? ModelAction.ProductActions.Block.Resonse }
            .map { ($0.productId, $0.result) }
            .receive(on: DispatchQueue.main)
            .sink { [unowned self] productId, result in
                
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
        let action: () -> Void
    }
}

extension ProductsViewModel {
    
    static func reduce(products: [Product], statements: [Statement], formatter: NumberFormatter = .amount, action: (ItemViewModel.ID) -> (() -> Void)) -> [ItemViewModel] {
        
        products.map { product in
            
            if let statement = statements.first(where: { $0.productId == product.id }) {
                
                let amount = formatter.string(for: statement.amount) ?? "\(statement.amount)"
                return .init(id: product.id, name: product.name, amount: amount, action: action(product.id))
                
            } else {
                
                return .init(id: product.id, name: product.name, amount: "UNKNOWN", action: action(product.id))
            }
        }
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
