//
//  SwipeView.swift
//  SimpleLiveTVOS
//
//  Created by pc on 2024/1/4.
//

import SwiftUI
import Foundation

public typealias Action = (UISwipeGestureRecognizer.Direction) -> Void

struct SwipeRecognizerView: UIViewRepresentable {

    let action: Action
    
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        let upSwipeRecognizer = UISwipeGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.respondToSwipeGesture))
        upSwipeRecognizer.direction = .up
        
        let downSwipeRecognizer = UISwipeGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.respondToSwipeGesture))
        downSwipeRecognizer.direction = .down
        
        let leftSwipeRecognizer = UISwipeGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.respondToSwipeGesture))
        leftSwipeRecognizer.direction = .left
        
        let rightSwipeRecognizer = UISwipeGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.respondToSwipeGesture))
        rightSwipeRecognizer.direction = .right
        
        view.addGestureRecognizer(upSwipeRecognizer)
        view.addGestureRecognizer(downSwipeRecognizer)
        view.addGestureRecognizer(leftSwipeRecognizer)
        view.addGestureRecognizer(rightSwipeRecognizer)
        
        return view
    }
    
    public class Coordinator: NSObject, UIGestureRecognizerDelegate {
        public let action: Action
        
        public init(action: @escaping Action) {
            self.action = action
        }
        
        @objc func respondToSwipeGesture(gesture: UIGestureRecognizer) {
            guard let swipeGesture = gesture as? UISwipeGestureRecognizer else { return }
            action(swipeGesture.direction)
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(action: action)
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {}
}

struct SwipeModifier: ViewModifier {
    let action: Action
    
    func body(content: Content) -> some View {
        content
            .overlay {
                SwipeRecognizerView(action: action)
                    .onMoveCommand(perform: { direction in
                        switch direction {
                            case .down:
                                action(.down)
                            case .up:
                                action(.up)
                            case .left:
                                action(.left)
                            case .right:
                                action(.right)
                            @unknown default:
                                fatalError()
                        }
                    })
            }
    }
}


extension View {
    public func onSwipeGesture(perform: @escaping Action) -> some View {
        return self.modifier(SwipeModifier(action: perform))
    }
}

