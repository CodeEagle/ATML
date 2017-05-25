//
//  NSObject+KVOBlock.m
//  Toast
//
//  Created by 朱李宏 on 15/6/23.
//
//

#import "KVOBlock.h"
#import <objc/runtime.h>

@interface KVOBlockObserver : NSObject

@property (nonatomic, assign) id beObserver;                    //采用assign
@property (nonatomic, strong) NSString *keyPath;
@property (nonatomic, strong) KVOBlockChange observationBlock;

@end

@implementation KVOBlockObserver

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
    if (object == self.beObserver && [keyPath isEqualToString:self.keyPath]) {
        if (self.observationBlock) {
            id chgnew = [change valueForKey:NSKeyValueChangeNewKey];
            id chgold = [change valueForKey:NSKeyValueChangeOldKey];
            self.observationBlock(self.beObserver, chgold, chgnew);
        }
    }
}

- (void)dealloc
{
    if (self.beObserver) {
        [self.beObserver removeObserver:self forKeyPath:self.keyPath];
    }
    self.observationBlock = nil;
}

@end

@implementation NSObject (KVOBlock)

- (void)observeKeyPath:(NSString *)keyPath withBlock:(KVOBlockChange)observationBlock
{
    KVOBlockObserver *observer = [KVOBlockObserver new];
    observer.keyPath = keyPath;
    observer.beObserver = self;
    observer.observationBlock = observationBlock;
    [self addObserver:observer forKeyPath:keyPath options:(NSKeyValueObservingOptionNew | NSKeyValueObservingOptionOld) context:nil];
    NSDictionary * dict = @{@"keyPath" : observer};
    [self.associateObserverBlockArray addObject:dict];
}

- (void)removeObserverFor:(NSString *)keyPath {
    NSUInteger count = self.associateObserverBlockArray.count;
    for (NSUInteger i = 0; i < count; i++) {
        NSDictionary* item = self.associateObserverBlockArray[i];
        NSString *key = [item allKeys].firstObject;
        if ([key isEqualToString: keyPath] ) {
            [self.associateObserverBlockArray removeObjectAtIndex:i];
            break;
        }
    }
}

- (NSMutableArray *)associateObserverBlockArray
{
    static const char kRepresentedObject;
    NSMutableArray *array = objc_getAssociatedObject(self, &kRepresentedObject);
    if (!array) {
        array = [NSMutableArray array];
        objc_setAssociatedObject(self, &kRepresentedObject, array, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return array;
}

@end
