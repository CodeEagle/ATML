//
//  NSObject+KVOBlock.h
//  Toast
//
//  Created by 朱李宏 on 15/6/23.
//
//
#import <Foundation/Foundation.h>
//! Project version number for KVOBlock.
FOUNDATION_EXPORT double KVOBlockVersionNumber;

//! Project version string for KVOBlock.
FOUNDATION_EXPORT const unsigned char KVOBlockVersionString[];

typedef void(^KVOBlockChange) (__weak __nullable id self, __nullable id old, __nullable id newVal);

@interface NSObject (KVOBlock)
/**
 *  Safe KVO whitout manual remove observer
 *
 *  @param keyPath          keypath
 *  @param observationBlock three object (observingTarget, oldValue, newValue)
 */
- (void)observeKeyPath:(nonnull NSString*)keyPath withBlock:(nonnull KVOBlockChange)observationBlock;
- (void)removeObserverFor:(nonnull NSString*)keyPath;
@end
