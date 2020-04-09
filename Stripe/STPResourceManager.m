//
//  STPResourceManager.m
//  StripeiOS
//
//  Created by David Estes on 4/7/20.
//  Copyright © 2020 Stripe, Inc. All rights reserved.
//

#import "STPResourceManager.h"

typedef void(^STPResourceManagerImageUpdateBlock)(UIImage * _Nullable);
static NSTimeInterval const STPCacheExpirationInterval = 60 * 60 * 24 * 7;

@implementation STPResourceManager {
    dispatch_queue_t _resourceQueue;
    NSMutableDictionary<NSString *, UIImage *> *_imageCache;
    NSMutableDictionary<NSString *, NSDictionary *> *_jsonCache;
    NSMutableDictionary<NSString *, NSURLSessionTask *> *_pendingRequests;
    NSMutableDictionary<NSString *, NSMutableArray <STPResourceManagerImageUpdateBlock>*> *_completionBlocks;
}

+ (instancetype)sharedManager {
    static id sharedManager;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ sharedManager = [[self alloc] init]; });
    return sharedManager;
}

- (instancetype)init {
    self = [super init];
    _resourceQueue = dispatch_queue_create("Stripe Resource Cache", DISPATCH_QUEUE_CONCURRENT);
    _imageCache = [[NSMutableDictionary alloc] init];
    _jsonCache = [[NSMutableDictionary alloc] init];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(didReceiveMemoryWarning) name:UIApplicationDidReceiveMemoryWarningNotification object:nil];
    return self;
}

- (UIImage *)imageNamed:(NSString *)name {
    return [self imageNamed:name updateHandler:nil];
}

- (UIImage *)imageNamed:(NSString *)name updateHandler:(nullable void (^)(UIImage * _Nullable))updateHandler {
    // get image from cache
    UIImage *image = nil;
    @synchronized (_imageCache) {
        image = [_imageCache objectForKey:name];
    }
    if (image != nil) {
        return image;
    }
    // if not available, check disk cache:
    image = [UIImage imageWithContentsOfFile:[[self cacheUrlForResource:name] path]];
    if (image != nil) {
        @synchronized (_imageCache) {
            _imageCache[name] = image;
        }
        if (![self shouldRefreshResource:name]) { // if we don't need to refresh this, we can return here
            return image;
        }
    }
    if (image == nil) {
        // if no image in cache, fetch and return image from bundle
        image = [UIImage imageNamed:name];
    }
    // and if we still have nothing, return an empty UIImage of some sort as a placeholder
    if (image == nil) {
        image = [UIImage imageNamed:@"stp_icon_add"]; // TODO: replace this with placeholder image
    }
    // kick off the update request:
    dispatch_async(_resourceQueue, ^{
        @synchronized (self->_pendingRequests) {
            [self _addUpdateHandler:updateHandler forName:name];
            [self _downloadFile:name];
        }
    });
    return image;
}

- (BOOL)shouldRefreshResource:(NSString *)name {
    NSURL *cacheURL = [self cacheUrlForResource:name];
    NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:[cacheURL path] error:nil];
    if (attributes == nil || [[attributes fileModificationDate] timeIntervalSinceNow] > STPCacheExpirationInterval) {
        return YES;
    }
    return NO;
}

- (NSURL *)cacheUrlForResource:(NSString *)name
{
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
    NSString *temporaryDirectory = [paths objectAtIndex:0];
    NSString *filePath = [[temporaryDirectory stringByAppendingPathComponent:@"STPCache"] stringByAppendingPathComponent:name];
    return [NSURL fileURLWithPath:filePath];
}

- (void)_addUpdateHandler:(STPResourceManagerImageUpdateBlock)block forName:(NSString *)name {
    NSMutableArray<STPResourceManagerImageUpdateBlock> *blocks = [_completionBlocks objectForKey:name];
    if (blocks == nil) {
        blocks = [[NSMutableArray alloc] init];
        _completionBlocks[name] = blocks;
    }
    [blocks addObject:block];
}

- (NSDictionary *)jsonNamed:(NSString *)name {
    return [self jsonNamed:name updateHandler:nil];
}

- (NSDictionary *)jsonNamed:(NSString *)name updateHandler:(nullable void (^)(UIImage * _Nullable))updateHandler {
    // get image from cache
    
    // if no image in cache, fetch and return image from bundle
    
    // if nothing at all, return an empty UIImage (of the correct size?)
    if (updateHandler != nil) {
        // handle update
    }
    return nil;
}

- (void)_downloadFile:(NSString *)name {
    // TODO: add @2x or @3x here depending on our screen size. imageWithContentsOfFile and imageNamed will do this automatically. make sure the right name is still used for completion blocks.
    NSString *filename = [NSString stringWithFormat:@"https://d37fzvdshh1bs8.cloudfront.net/%@", name];
    NSURL *url = [[NSURL alloc] initWithString:filename];
    if ([_pendingRequests objectForKey:name]) {
        return; // we're still waiting on an existing request!
    }
    NSURLSessionDownloadTask *task = [[NSURLSession sharedSession] downloadTaskWithURL:url completionHandler:^(NSURL * _Nullable location, NSURLResponse * _Nullable response, NSError * _Nullable error) {
        if (error != nil || response == nil) {
            // handle error
            return;
        }
        UIImage *image = [UIImage imageWithContentsOfFile:[location path]];
        NSURL *destLocation = [self cacheUrlForResource:name];
        [[NSFileManager defaultManager] moveItemAtURL:location toURL:destLocation error:nil];

        @synchronized (self->_imageCache) {
            self->_imageCache[filename] = image;
            @synchronized (self->_pendingRequests) {
                [self->_pendingRequests removeObjectForKey:name];
                NSArray<STPResourceManagerImageUpdateBlock> *updates = [self->_completionBlocks objectForKey:name];
                for (STPResourceManagerImageUpdateBlock update in updates) {
                    update(image);
                }
                [self->_completionBlocks removeObjectForKey:name];
            }
        }
    }];
    [_pendingRequests setObject:task forKey:name];
    [task resume];
}

- (void)downloadFile:(NSString *)name {
    dispatch_async(_resourceQueue, ^{
        [self _downloadFile:name];
    });
}

- (void)prefetchImages {
//     do prefetch?
}

- (void)didReceiveMemoryWarning {
    @synchronized (_imageCache) {
        [_imageCache removeAllObjects];
    }
    @synchronized (_jsonCache) {
        [_jsonCache removeAllObjects];
    }
}

- (void)resetCache {
    @synchronized (_imageCache) {
        NSURL *resourceBaseURL = [self cacheUrlForResource:@""];
        [[NSFileManager defaultManager] removeItemAtURL:resourceBaseURL error:nil];
        [_imageCache removeAllObjects];
        [_jsonCache removeAllObjects];
    }
}

/*
- (void)downloadAllImages {
    NSDate *startTime = [NSDate date];
    NSLog(@"Starting download");
    for (int i = 1; i < 148; i++) {
        NSString *filename = [NSString stringWithFormat:@"https://d37fzvdshh1bs8.cloudfront.net/a%i.png", i];
        NSURL *url = [[NSURL alloc] initWithString:filename];
        NSURLSessionDownloadTask *task = [[NSURLSession sharedSession] downloadTaskWithURL:url completionHandler:^(NSURL * _Nullable location, NSURLResponse * _Nullable response, NSError * _Nullable error) {
            if (error != nil || response == nil) {
                // handle error
                return;
            }
            UIImage *image = [UIImage imageWithContentsOfFile:[location path]];
            @synchronized (self->_imageCache) {
                self->_imageCache[filename] = image;
                if ([self->_imageCache count] == 147) {
                    NSTimeInterval interval = [startTime timeIntervalSinceNow];
                    NSLog(@"Done with download in %f seconds", interval);
                }
            }
        }];
        [task resume];
    }
}
*/
@end
