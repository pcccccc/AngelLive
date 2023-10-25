//
//  SwipeGestureActions.swift
//  SimpleLiveTVOS
//
//  Created by pangchong on 2023/10/24.
//

import SwiftUI
import GameController

// MARK: - View+swipeGestures
struct SwipeGestureActions: ViewModifier
{
    // swipeDistance is how much x/y values needs to be acumelated by a gesture in order to consider a swipe (the distance the finger must travel)
    let swipeDistance: Float = 0.7
    // how much pause in milliseconds should be between gestures in order for a gesture to be considered a new gesture and not a remenat x/y values from the previous gesture
    let secondsBetweenInteractions: Double = 0.2
    
    // the closures to execute when up/down/left/right gesture are detected
    var onUp: () -> Void = {}
    var onDown: () -> Void = {}
    var onRight: () -> Void = {}
    var onLeft: () -> Void = {}

    @State var lastY: Float = 0
    @State var lastX: Float = 0
    @State var totalYSwipeDistance: Float = 0
    @State var totalXSwipeDistance: Float = 0
    @State var lastInteractionTimeInterval: TimeInterval = Date().timeIntervalSince1970
    @State var isNewSwipe: Bool = true
    
    func resetCounters(x: Float, y: Float)
    {
        isNewSwipe = true
        lastY = y // start counting from the y point the finger is touching
        totalYSwipeDistance = 0
        lastX = x // start counting from the x point the finger is touching
        totalXSwipeDistance = 0
    }

    func body(content: Content) -> some View
    {
        content
            .onAppear(perform: {
                let gcController = GCController.controllers().first
                let microGamepad = gcController!.microGamepad
                microGamepad!.reportsAbsoluteDpadValues = false // assumes the location where the user first touches the pad is the origin value (0.0,0.0)
                let currentHandler = microGamepad!.dpad.valueChangedHandler
                microGamepad!.dpad.valueChangedHandler = { pad, x, y in
                    // if there is already a hendler set - execute it as well
                    if currentHandler != nil {
                        currentHandler!(pad, x, y)
                    }
                    
                    /* check how much time passed since the last interaction on the siri remote,
                     * if enough time has passed - reset counters and consider these coming values as a new gesture values
                     */
                    let nowTimestamp = Date().timeIntervalSince1970
                    let elapsedNanoSinceLastInteraction = nowTimestamp - lastInteractionTimeInterval
                    lastInteractionTimeInterval = nowTimestamp // update the last interaction interval
                    if elapsedNanoSinceLastInteraction > secondsBetweenInteractions
                    {
                        resetCounters(x: x, y: y)
                    }
                    
                    /* accumelate the Y axis swipe travel distance */
                    let currentYSwipeDistance = y - lastY
                    lastY = y
                    totalYSwipeDistance = totalYSwipeDistance + currentYSwipeDistance
                    
                    /* accumelate the X axis swipe travel distance */
                    let currentXSwipeDistance = x - lastX
                    lastX = x
                    totalXSwipeDistance = totalXSwipeDistance + currentXSwipeDistance
                    
//                    print("y: \(y), x: \(x), totalY: \(totalYSwipeDistance) totalX: \(totalXSwipeDistance)")
                    
                    /* check if swipe travel goal has been reached in one of the directions (up/down/left/right)
                     * as long as it is consedered a new swipe (and not a swipe that was already detected and executed
                     * and waiting for a few milliseconds stop between interactions)
                     */
                    if (isNewSwipe)
                    {
                        if totalYSwipeDistance > swipeDistance && totalYSwipeDistance > 0 // swipe up detected
                        {
                            isNewSwipe = false // lock so next values will be disregarded until a few milliseconds of 'remote silence' achieved
                            onUp() // execute the appropriate closure for this detected swipe
                        }
                        else if totalYSwipeDistance < -swipeDistance && totalYSwipeDistance < 0 // swipe down detected
                        {
                            isNewSwipe = false
                            onDown()
                        }
                        else if totalXSwipeDistance > swipeDistance && totalXSwipeDistance > 0 // swipe right detected
                        {
                            isNewSwipe = false
                            onRight()
                        }
                        else if totalXSwipeDistance < -swipeDistance && totalXSwipeDistance < 0 // swipe left detected
                        {
                            isNewSwipe = false
                            onLeft()
                        }
                        else
                        {
                            //print(">>> tap")
                        }
                    }
                }
            })
    }
}

extension View
{
    func swipeGestures(onUp: @escaping () -> Void = {},
                       onDown: @escaping () -> Void = {},
                       onRight: @escaping () -> Void = {},
                       onLeft: @escaping () -> Void = {}) -> some View
    {
        self.modifier(SwipeGestureActions(onUp: onUp,
                                          onDown: onDown,
                                          onRight: onRight,
                                          onLeft: onLeft))
    }
}
