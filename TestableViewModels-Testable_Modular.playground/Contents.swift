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
    
    var content: AnyPublisher<[ProductsViewModel.ItemViewModel], Never> { get }
    var amountFormatter: NumberFormatter { get }

    func itemDidTapped(itemId: ProductsViewModel.ItemViewModel.ID)
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
}

extension ProductsViewModel {
    
    func bind() {
        
        contentService.content
            .receive(on: DispatchQueue.main)
            .sink { [unowned self] items in
   
                withAnimation {
                    
                    state = .items(items)
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
