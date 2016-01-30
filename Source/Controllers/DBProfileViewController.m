//
//  DBProfileViewController.m
//  Pods
//
//  Created by Devon Boyer on 2015-12-18.
//
//

#import "DBProfileViewController.h"
#import "DBProfileDetailsView.h"
#import "DBProfilePictureView.h"
#import "DBProfileCoverPhotoView.h"
#import "DBProfileTitleView.h"
#import "DBProfileSegmentedControlView.h"
#import "DBProfileNavigationView.h"
#import "DBProfileContentPresenting.h"
#import "DBProfileImageEffects.h"

const CGFloat DBProfileViewControllerProfilePictureSizeNormal = 72.0;
const CGFloat DBProfileViewControllerProfilePictureSizeLarge = 82.0;

static const CGFloat DBProfileViewControllerPullToRefreshDistance = 80.0;
static const CGFloat DBProfileViewControllerNavigationBarHeightRegular = 64.0;
static const CGFloat DBProfileViewControllerNavigationBarHeightCompact = 44.0;

static void * DBProfileViewControllerContentOffsetKVOContext = &DBProfileViewControllerContentOffsetKVOContext;
static NSString * const DBProfileViewControllerContentOffsetKeyPath = @"contentOffset";

@interface DBProfileViewController ()
{
    BOOL _hasAppeared;
    BOOL _shouldScrollToTop;
    CGPoint _contentOffset;
}

@property (nonatomic, getter=isRefreshing) BOOL refreshing;
@property (nonatomic, strong) NSMutableArray *mutableContentViewControllers;
@property (nonatomic, strong) NSCache *contentOffsetCache;
@property (nonatomic, strong) NSCache *blurredImageCache;

// Views
@property (nonatomic, strong) UIViewController *containerViewController;
@property (nonatomic, strong) DBProfileNavigationView *navigationView;
@property (nonatomic, strong) UIActivityIndicatorView *activityIndicator;

// Constraints
@property (nonatomic, strong) NSLayoutConstraint *detailsViewTopConstraint;
@property (nonatomic, strong) NSLayoutConstraint *coverPhotoViewTopConstraint;
@property (nonatomic, strong) NSLayoutConstraint *coverPhotoViewHeightConstraint;
@property (nonatomic, strong) NSLayoutConstraint *profilePictureViewLeftConstraint;
@property (nonatomic, strong) NSLayoutConstraint *profilePictureViewRightConstraint;
@property (nonatomic, strong) NSLayoutConstraint *profilePictureViewCenterXConstraint;
@property (nonatomic, strong) NSLayoutConstraint *profilePictureViewTopConstraint;
@property (nonatomic, strong) NSLayoutConstraint *profilePictureViewWidthConstraint;
@property (nonatomic, strong) NSLayoutConstraint *coverPhotoViewBottomConstraint;
@property (nonatomic, strong) NSLayoutConstraint *coverPhotoViewTopLayoutGuideConstraint;
@property (nonatomic, strong) NSLayoutConstraint *coverPhotoViewTopSuperviewConstraint;

// Gestures
@property (nonatomic, strong) UITapGestureRecognizer *coverPhotoTapGestureRecognizer;
@property (nonatomic, strong) UITapGestureRecognizer *profilePictureTapGestureRecognizer;

@end

@implementation DBProfileViewController

#pragma mark - Initialization

- (instancetype)init {
    self = [super init];
    if (self) {
        [self _commonInit];
    }
    return self;
}

- (instancetype)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil {
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    if (self) {
        [self _commonInit];
    }
    return self;
}

- (instancetype)initWithCoder:(NSCoder *)aDecoder {
    self = [super initWithCoder:aDecoder];
    if (self) {
        [self _commonInit];
    }
    return self;
}

- (instancetype)initWithContentViewControllers:(NSArray *)contentViewControllers {
    self = [super init];
    if (self) {
        [self.mutableContentViewControllers addObjectsFromArray:contentViewControllers];
        [self _commonInit];
    }
    return self;
}

- (void)_commonInit {
    _segmentedControlView = [[DBProfileSegmentedControlView alloc] init];
    _detailsView = [[DBProfileDetailsView alloc] init];
    _profilePictureView = [[DBProfilePictureView alloc] init];
    _coverPhotoView = [[DBProfileCoverPhotoView alloc] init];
    _navigationView = [[DBProfileNavigationView alloc] init];
    _containerViewController = [[UIViewController alloc] init];
    _profilePictureTapGestureRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleProfilePictureTapGesture:)];
    _coverPhotoTapGestureRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleCoverPhotoTapGesture:)];
    _activityIndicator = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhite];

    NSCache *contentOffsetCache = [[NSCache alloc] init];
    contentOffsetCache.name = @"DBProfileViewController.contentOffsetCache";
    contentOffsetCache.countLimit = 200;
    _contentOffsetCache = contentOffsetCache;
    
    NSCache *blurredImageCache = [[NSCache alloc] init];
    blurredImageCache.name = @"DBProfileViewController.blurredImageCache";
    blurredImageCache.countLimit = 200;
    _blurredImageCache = blurredImageCache;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    
    if (self.visibleContentViewController) {
        UIScrollView *scrollView = [self.visibleContentViewController contentScrollView];
        [self endObservingContentOffsetForScrollView:scrollView];
    }
    
    [self.blurredImageCache removeAllObjects];
    self.blurredImageCache = nil;
    
    [self.contentOffsetCache removeAllObjects];
    self.contentOffsetCache = nil;
}

#pragma mark - View Lifecycle

- (void)loadView {
    [super loadView];
    
    [self addChildViewController:self.containerViewController];
    [self.view addSubview:self.containerViewController.view];
    self.containerViewController.view.frame = self.view.frame;
    self.containerViewController.view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.containerViewController didMoveToParentViewController:self];
    
    [self.view addSubview:self.navigationView];

    [self.navigationView setTranslatesAutoresizingMaskIntoConstraints:NO];
    
    // Auto Layout
    [self configureNavigationViewLayoutConstraints];
    
    // Gestures
    [self.coverPhotoView addGestureRecognizer:self.coverPhotoTapGestureRecognizer];
    self.coverPhotoView.userInteractionEnabled = YES;
    
    [self.profilePictureView addGestureRecognizer:self.profilePictureTapGestureRecognizer];
    self.profilePictureView.userInteractionEnabled = YES;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(applicationWillEnterForeground:)
                                                 name:UIApplicationWillEnterForegroundNotification
                                               object:nil];
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(applicationDidEnterBackground:)
                                                 name:UIApplicationDidEnterBackgroundNotification
                                               object:nil];
    
    [self.segmentedControlView.segmentedControl addTarget:self
                                                   action:@selector(segmentChanged:)
                                         forControlEvents:UIControlEventValueChanged];
    
    [self configureDefaults];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    
    [self.view setNeedsLayout];
    [self.view layoutIfNeeded];
    [self.view setNeedsUpdateConstraints]; // performance hit while loading the view
    
    [self scrollVisibleContentViewControllerToTop];
    
    if (self.coverPhotoMimicsNavigationBar) {
        [self.navigationController setNavigationBarHidden:YES animated:YES];
        [self.navigationController.interactivePopGestureRecognizer setDelegate:nil];
    }
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    
    _hasAppeared = YES;

    NSAssert([self numberOfContentViewControllers] > 0, @"`DBProfileViewController` must have at least one content view controller.");
}

- (void)updateViewConstraints {
    [self updateCoverPhotoViewLayoutConstraints];
    [self updateProfilePictureViewLayoutConstraints];
    [super updateViewConstraints];
}

- (void)configureDefaults {
    self.coverPhotoOptions = DBProfileCoverPhotoOptionStretch;
    self.coverPhotoStyle = DBProfileCoverPhotoStyleDefault;
    self.coverPhotoMimicsNavigationBar = YES;
    self.coverPhotoHeightMultiplier = 0.2;
    self.profilePictureAlignment = DBProfilePictureAlignmentLeft;
    self.profilePictureSize = DBProfilePictureSizeNormal;
    self.profilePictureInset = UIEdgeInsetsMake(0, 15, DBProfileViewControllerProfilePictureSizeNormal/2.0 - 10, 0);
    self.allowsPullToRefresh = YES;
    
    self.segmentedControlView.backgroundColor = [UIColor whiteColor];
    self.segmentedControlView.segmentedControl.tintColor = [UIColor grayColor];
    
    self.navigationView.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithImage:[UIImage imageNamed:@"back-icon"] style:UIBarButtonItemStylePlain target:self action:@selector(back:)];
}

#pragma mark - Status Bar

- (UIStatusBarStyle)preferredStatusBarStyle {
    return UIStatusBarStyleLightContent;
}

#pragma mark - Size Classes

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    
    [self configureContentViewControllers];
    
    UIScrollView *scrollView = [self.visibleContentViewController contentScrollView];
    [scrollView setContentOffset:_contentOffset];
}

#pragma mark - Getters

- (NSArray *)contentViewControllers {
    return (NSArray *)self.mutableContentViewControllers;
}

- (NSMutableArray *)mutableContentViewControllers {
    if (!_mutableContentViewControllers) {
        _mutableContentViewControllers = [NSMutableArray array];
    }
    return _mutableContentViewControllers;
}

#pragma mark - Setters

- (void)setCoverPhotoHeightMultiplier:(CGFloat)coverPhotoHeightMultiplier {
    NSAssert(coverPhotoHeightMultiplier > 0 && coverPhotoHeightMultiplier <= 1, @"`coverPhotoHeightMultiplier` must be greater than 0 or less than or equal to 1.");
    if (_coverPhotoHeightMultiplier == coverPhotoHeightMultiplier) return;
    _coverPhotoHeightMultiplier = coverPhotoHeightMultiplier;
    [self.view setNeedsUpdateConstraints];
}

- (void)setCoverPhotoOptions:(DBProfileCoverPhotoOptions)coverPhotoOptions {
    _coverPhotoOptions = coverPhotoOptions;
    [self.view setNeedsUpdateConstraints];
}

- (void)setCoverPhotoStyle:(DBProfileCoverPhotoStyle)coverPhotoStyle {
    if (self.coverPhotoStyle == DBProfileCoverPhotoStyleNone) {
        NSAssert(!self.coverPhotoMimicsNavigationBar || !self.allowsPullToRefresh, @"`DBProfileCoverPhotoStyleNone` is mutually exclusive with `coverPhotoMimicsNavigationBar` and `allowsPullToRefresh`");
    }
    if (_coverPhotoStyle == coverPhotoStyle) return;
    _coverPhotoStyle = coverPhotoStyle;
    [self.view setNeedsUpdateConstraints];
}

- (void)setProfilePictureInset:(UIEdgeInsets)profilePictureInset {
    if (UIEdgeInsetsEqualToEdgeInsets(_profilePictureInset, profilePictureInset)) return;
    _profilePictureInset = profilePictureInset;
    [self.view setNeedsUpdateConstraints];
}

- (void)setProfilePictureAlignment:(DBProfilePictureAlignment)profilePictureAlignment {
    if (_profilePictureAlignment == profilePictureAlignment) return;
    _profilePictureAlignment = profilePictureAlignment;
    [self.view setNeedsUpdateConstraints];
}

- (void)setProfilePictureSize:(DBProfilePictureSize)profilePictureSize {
    if (_profilePictureSize == profilePictureSize) return;
    _profilePictureSize = profilePictureSize;
    [self.view setNeedsUpdateConstraints];
}

- (void)setCoverPhotoMimicsNavigationBar:(BOOL)coverPhotoMimicsNavigationBar {
    if (coverPhotoMimicsNavigationBar) {
        //NSAssert(self.coverPhotoStyle != DBProfileCoverPhotoStyleNone, @"`DBProfileCoverPhotoStyleNone` is mutually exclusive with `coverPhotoMimicsNavigationBar` and `allowsPullToRefresh`");
    }
    if (coverPhotoMimicsNavigationBar && self.automaticallyAdjustsScrollViewInsets) {
        NSLog(@"Warning: `automaticallyAdjustsScrollViewInsets` should be set to NO when using coverPhotoMimicsNavigationBar");
    }
    _coverPhotoMimicsNavigationBar = coverPhotoMimicsNavigationBar;
    self.navigationView.hidden = !coverPhotoMimicsNavigationBar;
}

- (void)setAllowsPullToRefresh:(BOOL)allowsPullToRefresh {
    if (allowsPullToRefresh) {
        //NSAssert(self.coverPhotoStyle != DBProfileCoverPhotoStyleNone, @"`DBProfileCoverPhotoStyleNone` is mutually exclusive with `coverPhotoMimicsNavigationBar` and `allowsPullToRefresh`");
    }
    _allowsPullToRefresh = allowsPullToRefresh;
}

- (void)setDetailsView:(UIView *)detailsView {
    NSAssert(detailsView, @"detailsView cannot be nil");
    _detailsView = detailsView;
    [self configureVisibleViewController:self.visibleContentViewController];
}

#pragma mark - Action Responders

- (void)back:(id)sender {
    [self.navigationController popViewControllerAnimated:YES];
}

- (void)segmentChanged:(id)sender {
    NSInteger selectedSegmentIndex = [self.segmentedControlView.segmentedControl selectedSegmentIndex];
    [self setVisibleContentViewControllerAtIndex:selectedSegmentIndex];
    [self updateViewConstraints];
}

- (void)handleProfilePictureTapGesture:(UITapGestureRecognizer *)sender {
    [self notifyDelegateOfProfilePictureSelection:self.profilePictureView.imageView];
}

- (void)handleCoverPhotoTapGesture:(UITapGestureRecognizer *)sender {
    [self notifyDelegateOfCoverPhotoSelection:self.coverPhotoView.imageView];
}

#pragma mark - Configuring Cover Photo

- (void)setCoverPhoto:(UIImage *)coverPhoto animated:(BOOL)animated {

    UIImage *croppedImage = [DBProfileImageEffects imageByCroppingImage:coverPhoto withSize:self.coverPhotoView.frame.size];
    
    self.coverPhotoView.imageView.image = croppedImage;
    
    if (animated) {
        self.coverPhotoView.imageView.alpha = 0;
        [UIView animateWithDuration: 0.3 animations:^{
            self.coverPhotoView.imageView.alpha = 1;
        }];
    }
    
    if (croppedImage) {
        // FIXME: Filling blurred image cache is very hard on memory. Is there a way we can cancel this in viewWillDissappear:?
        __weak DBProfileViewController *weakSelf = self;
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            [weakSelf fillBlurredImageCacheWithImage:croppedImage];
        });
    }
}

#pragma mark - Configuring Profile Picture

- (void)setProfilePicture:(UIImage *)profilePicture animated:(BOOL)animated {
    self.profilePictureView.imageView.image = profilePicture;

    if (animated) {
        self.profilePictureView.imageView.alpha = 0;
        [UIView animateWithDuration: 0.3 animations:^{
            self.profilePictureView.imageView.alpha = 1;
        }];
    }
}

#pragma mark - Adding and Removing Content View Controllers

- (void)addContentViewControllers:(NSArray *)contentViewControllers {
    [self.mutableContentViewControllers addObjectsFromArray:contentViewControllers];
    [self configureContentViewControllers];
    [self scrollVisibleContentViewControllerToTop];
}

- (void)addContentViewController:(UIViewController<DBProfileContentPresenting> *)contentViewController {
    NSAssert(contentViewController, @"contentViewController cannot be nil");
    
    [self.mutableContentViewControllers addObject:contentViewController];
    [self configureContentViewControllers];
    [self scrollVisibleContentViewControllerToTop];
}

- (void)insertContentViewController:(UIViewController<DBProfileContentPresenting> *)contentViewController atIndex:(NSUInteger)index {
    NSAssert(contentViewController, @"contentViewController cannot be nil");
    
    [self.mutableContentViewControllers insertObject:contentViewController atIndex:index];
    [self configureContentViewControllers];
    [self scrollVisibleContentViewControllerToTop];
}

- (void)removeContentViewControllerAtIndex:(NSUInteger)index {
    if (index < [self numberOfContentViewControllers]) {
        [self.mutableContentViewControllers removeObjectAtIndex:index];
        [self configureContentViewControllers];
        [self scrollVisibleContentViewControllerToTop];
    }
}

- (void)setVisibleContentViewControllerAtIndex:(NSUInteger)index {
    UIScrollView *scrollView = [self.visibleContentViewController contentScrollView];
    if (self.visibleContentViewController) {
        [self endObservingContentOffsetForScrollView:scrollView];
    }
    
    CGFloat topInset = CGRectGetMaxY(self.navigationView.frame) + CGRectGetHeight(self.segmentedControlView.frame);
    _shouldScrollToTop = scrollView.contentOffset.y < topInset;
    _contentOffset = scrollView.contentOffset;
    
    // Cache content offset of disappearing scroll view
    [self cacheContentOffset:scrollView.contentOffset forKey:[self titleForVisibleContentViewController]];
    
    // Remove previous view controller from container
    [self removeViewControllerFromContainer:self.visibleContentViewController];
    
    UIViewController<DBProfileContentPresenting> *visibleContentViewController = self.contentViewControllers[index];
    
    // Add visible view controller to container
    [self addViewControllerToContainer:visibleContentViewController];

    _visibleContentViewController = visibleContentViewController;

    [self.segmentedControlView.segmentedControl setSelectedSegmentIndex:index];
    [self configureVisibleViewController:visibleContentViewController];
}

#pragma mark - Configuring Pull-To-Refresh

- (void)endRefreshing {
    self.refreshing = NO;
    [self endRefreshAnimations];
}

- (void)startRefreshAnimations {
    [self.activityIndicator startAnimating];
}

- (void)endRefreshAnimations {
    [self.activityIndicator stopAnimating];
}

#pragma mark - Delegate

- (void)notifyDelegateOfProfilePictureSelection:(UIImageView *)imageView {
    if ([self respondsToSelector:@selector(profileViewController:didSelectProfilePicture:)]) {
        [self.delegate profileViewController:self didSelectProfilePicture:imageView];
    }
}

- (void)notifyDelegateOfCoverPhotoSelection:(UIImageView *)imageView {
    if ([self respondsToSelector:@selector(profileViewController:didSelectCoverPhoto:)]) {
        [self.delegate profileViewController:self didSelectCoverPhoto:imageView];
    }
}

- (void)notifyDelegateOfPullToRefresh {
    if ([self respondsToSelector:@selector(profileViewControllerDidPullToRefresh:)]) {
        [self.delegate profileViewControllerDidPullToRefresh:self];
    }
}

#pragma mark - Helpers

- (NSUInteger)visibleContentViewControllerIndex {
    return [self.segmentedControlView.segmentedControl selectedSegmentIndex];
}

- (NSInteger)numberOfContentViewControllers {
    return [self.contentViewControllers count];
}

- (UIScrollView *)scrollViewForVisibleContentViewController {
    NSAssert(self.visibleContentViewController, @"visibleContentViewController cannot be nil");
    NSUInteger currentlySelectedIndex = [self visibleContentViewControllerIndex];
    return [self scrollViewForContentViewControllerAtIndex:currentlySelectedIndex];
}

- (NSString *)titleForVisibleContentViewController {
    NSUInteger currentlySelectedIndex = [self visibleContentViewControllerIndex];
    return [self titleForContentViewControllerAtIndex:currentlySelectedIndex];
}

- (NSString *)subtitleForVisibleContentViewController {
    NSUInteger currentlySelectedIndex = [self visibleContentViewControllerIndex];
    return [self subtitleForContentViewControllerAtIndex:currentlySelectedIndex];
}

- (UIScrollView *)scrollViewForContentViewControllerAtIndex:(NSUInteger)index {
    UIViewController<DBProfileContentPresenting> *viewController;
    return [viewController contentScrollView];
}

- (NSString *)titleForContentViewControllerAtIndex:(NSUInteger)index {
    if (index >= [self numberOfContentViewControllers]) return nil;
    UIViewController<DBProfileContentPresenting> *viewController = self.contentViewControllers[index];
    NSString *contentTitle = [viewController contentTitle];
    NSAssert(contentTitle && [contentTitle length] > 0, @"contentTitle cannot be nil");
    return contentTitle;
}

- (NSString *)subtitleForContentViewControllerAtIndex:(NSUInteger)index {
    if (index >= [self numberOfContentViewControllers]) return nil;
    UIViewController<DBProfileContentPresenting> *viewController = self.contentViewControllers[index];
    if ([viewController respondsToSelector:@selector(contentSubtitle)]) {
        return [viewController contentSubtitle];
    }
    return nil;
}

- (void)cacheContentOffset:(CGPoint)contentOffset forKey:(NSString *)key {
    [self.contentOffsetCache setObject:[NSValue valueWithCGPoint:contentOffset] forKey:key];
}

- (CGPoint)cachedContentOffsetForKey:(NSString *)key {
    return [[self.contentOffsetCache objectForKey:key] CGPointValue];
}

- (void)scrollVisibleContentViewControllerToTop {
    UIScrollView *scrollView = [self.visibleContentViewController contentScrollView];
    [scrollView setContentOffset:CGPointMake(0, -scrollView.contentInset.top)];
}

- (void)resetContentOffsetForScrollView:(UIScrollView *)scrollView {
    CGPoint contentOffset = scrollView.contentOffset;
    contentOffset.y = -(CGRectGetMaxY(self.navigationView.frame) + CGRectGetHeight(self.segmentedControlView.frame));
    [scrollView setContentOffset:contentOffset];
}

- (void)configureVisibleViewController:(UIViewController<DBProfileContentPresenting> *)visibleViewController {
    UIScrollView *scrollView = [visibleViewController contentScrollView];
    
    [self.coverPhotoView removeFromSuperview];
    [self.detailsView removeFromSuperview];
    [self.profilePictureView removeFromSuperview];
    [self.segmentedControlView removeFromSuperview];
    [self.activityIndicator removeFromSuperview];
    
    [self.coverPhotoView setTranslatesAutoresizingMaskIntoConstraints:NO];
    [self.detailsView setTranslatesAutoresizingMaskIntoConstraints:NO];
    [self.profilePictureView setTranslatesAutoresizingMaskIntoConstraints:NO];
    [self.segmentedControlView setTranslatesAutoresizingMaskIntoConstraints:NO];
    [self.activityIndicator setTranslatesAutoresizingMaskIntoConstraints:NO];
    
    [scrollView addSubview:self.detailsView];
    [scrollView addSubview:self.coverPhotoView];
    [scrollView addSubview:self.profilePictureView];
    [scrollView addSubview:self.activityIndicator];
    
    // TODO: Check if we need to install the cover photo
    
    // Check if we need to install the segmented control
    if ([self numberOfContentViewControllers] > 1) {
        [scrollView addSubview:self.segmentedControlView];
        [self configureSegmentedControlViewLayoutConstraintsWithScrollView:scrollView];
    } else {
        self.segmentedControlView.frame = CGRectZero;
    }
    
    [self configureCoverPhotoViewLayoutConstraintsWithScrollView:scrollView];
    [self configureDetailsViewLayoutConstraintsWithScrollView:scrollView];
    [self configureProfilePictureViewLayoutConstraintsWithScrollView:scrollView];
    [self configureActivityIndicatorLayoutConstraintsWithScrollView:scrollView];

    [scrollView setNeedsLayout];
    [scrollView layoutIfNeeded];
    
    [self.view setNeedsUpdateConstraints];
    
    // Adjust contentInset
    [self adjustContentInsetForScrollView:scrollView];
    
    // Begin observing contentOffset
    [self beginObservingContentOffsetForScrollView:scrollView];
    
    // Reset the content offset
    if (!_hasAppeared) {
        [self scrollVisibleContentViewControllerToTop];
    } else if (!_shouldScrollToTop) {
        [self resetContentOffsetForScrollView:scrollView];
        
        // TOOD: Check if content size is too small (not enough rows to fill the screen)
    
        // Restore content offset for scroll view from cache
        CGPoint contentOffset = [self cachedContentOffsetForKey:[self titleForVisibleContentViewController]];
        if (contentOffset.y > scrollView.contentOffset.y && !self.automaticallyAdjustsScrollViewInsets) {
            [scrollView setContentOffset:contentOffset];
        }
    } else {
        [scrollView setContentOffset:_contentOffset];
    }
    [scrollView flashScrollIndicators];
    
    self.navigationView.titleView.titleLabel.text = self.title;
    self.navigationView.titleView.subtitleLabel.text = [self subtitleForVisibleContentViewController];
}

- (void)configureContentViewControllers {
    NSInteger selectedSegmentIndex = self.segmentedControlView.segmentedControl.selectedSegmentIndex;
    
    [self.segmentedControlView.segmentedControl removeAllSegments];
    
    for (NSInteger i = 0; i < [self numberOfContentViewControllers]; i++) {
        NSString *title = [self titleForContentViewControllerAtIndex:i];
        [self.segmentedControlView.segmentedControl insertSegmentWithTitle:title atIndex:i animated:NO];
    }
    
    // Set the selected segment index
    if ([self numberOfContentViewControllers] > 0) {
        if (selectedSegmentIndex == UISegmentedControlNoSegment) {
            [self setVisibleContentViewControllerAtIndex:0];
        } else {
            [self setVisibleContentViewControllerAtIndex:selectedSegmentIndex];
        }
    }
}

- (void)adjustContentInsetForScrollView:(UIScrollView *)scrollView {
    CGFloat topInset = CGRectGetHeight(self.segmentedControlView.frame) + CGRectGetHeight(self.detailsView.frame) + CGRectGetHeight(self.coverPhotoView.frame);
    
    UIEdgeInsets contentInset = scrollView.contentInset;
    if (self.coverPhotoOptions & DBProfileCoverPhotoOptionExtended) topInset -= CGRectGetHeight(self.detailsView.frame);
    contentInset.top = (self.automaticallyAdjustsScrollViewInsets) ? topInset + [self.topLayoutGuide length] : topInset;
    
    scrollView.contentInset = contentInset;
    
    // Cover photo inset
    self.coverPhotoViewTopConstraint.constant = -topInset;
    
    // Details view inset
    if (self.coverPhotoOptions & DBProfileCoverPhotoOptionExtended) {
        topInset -= (CGRectGetHeight(self.coverPhotoView.frame) - CGRectGetHeight(self.detailsView.frame));
        [scrollView insertSubview:self.detailsView aboveSubview:self.coverPhotoView];
    } else {
        topInset -= CGRectGetHeight(self.coverPhotoView.frame);
    }
    self.detailsViewTopConstraint.constant = -topInset;
}

- (void)addViewControllerToContainer:(UIViewController *)viewController {
    [self.containerViewController addChildViewController:viewController];
    [self.containerViewController.view addSubview:viewController.view];
    viewController.view.frame = self.containerViewController.view.frame;
    [viewController didMoveToParentViewController:self];
}

- (void)removeViewControllerFromContainer:(UIViewController *)viewController {
    [viewController willMoveToParentViewController:nil];
    [viewController.view removeFromSuperview];
    [viewController removeFromParentViewController];
}

#pragma mark - KVO

- (void)beginObservingContentOffsetForScrollView:(UIScrollView *)scrollView {
    if (scrollView) {
        [scrollView addObserver:self
                     forKeyPath:DBProfileViewControllerContentOffsetKeyPath
                        options:0
                        context:&DBProfileViewControllerContentOffsetKVOContext];
    }
}


- (void)endObservingContentOffsetForScrollView:(UIScrollView *)scrollView {
    if (scrollView) {
        [scrollView removeObserver:self
                        forKeyPath:DBProfileViewControllerContentOffsetKeyPath];
    }
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary<NSString *,id> *)change context:(void *)context {
    
    if ([keyPath isEqualToString:DBProfileViewControllerContentOffsetKeyPath] && context == DBProfileViewControllerContentOffsetKVOContext) {
        UIScrollView *scrollView = (UIScrollView *)object;
        CGPoint contentOffset = scrollView.contentOffset;
        contentOffset.y += scrollView.contentInset.top;
        [self updateSubviewsWithContentOffset:contentOffset];
        [self handlePullToRefreshWithScrollView:scrollView];
        
        if (self.coverPhotoMimicsNavigationBar) {
            if (contentOffset.y < CGRectGetHeight(self.coverPhotoView.frame) - self.coverPhotoViewBottomConstraint.constant) {
                [scrollView insertSubview:self.profilePictureView aboveSubview:self.coverPhotoView];
            } else {
                [scrollView insertSubview:self.coverPhotoView aboveSubview:self.profilePictureView];
            }
        }
    }
}

#pragma mark - Pull To Refresh

- (void)handlePullToRefreshWithScrollView:(UIScrollView *)scrollView {
    if (!self.allowsPullToRefresh) return;
    CGPoint contentOffset = scrollView.contentOffset;
    contentOffset.y += scrollView.contentInset.top;
    if (scrollView.isDragging && contentOffset.y < 0) {
        [self startRefreshAnimations];
    } else if (!scrollView.isDragging && !self.refreshing && contentOffset.y < -DBProfileViewControllerPullToRefreshDistance) {
        self.refreshing = YES;
        [self notifyDelegateOfPullToRefresh];
    }
    
    BOOL shouldEndRefreshAnimations = !self.refreshing && self.activityIndicator.isAnimating;
    if (!scrollView.isDragging && contentOffset.y >= 0 && shouldEndRefreshAnimations) {
        [self endRefreshAnimations];
    }
}

#pragma mark - Updating Subviews On Scroll

- (void)updateSubviewsWithContentOffset:(CGPoint)contentOffset {
    [self updateCoverPhotoViewWithContentOffset:contentOffset];
    [self updateProfilePictureViewWithContentOffset:contentOffset];
    [self updateTitleViewWithContentOffset:contentOffset];
}

- (void)updateCoverPhotoViewWithContentOffset:(CGPoint)contentOffset {
    
    CGFloat distance = CGRectGetHeight(self.coverPhotoView.frame) - CGRectGetMaxY(self.navigationView.frame);
    
    if (contentOffset.y <= 0) {
        if (self.coverPhotoOptions & DBProfileCoverPhotoOptionStretch) {
            self.coverPhotoViewHeightConstraint.constant = -contentOffset.y;
        }
        distance *= 0.5;
    }
    
    CGFloat percent = MAX(MIN(1 - (distance - fabs(contentOffset.y))/distance, 1), 0);
    UIImage *blurredImage = [self blurredImageAt:percent];
    if (blurredImage) self.coverPhotoView.imageView.image = blurredImage;
}

- (void)updateProfilePictureViewWithContentOffset:(CGPoint)contentOffset {
    CGFloat coverPhotoOffset = CGRectGetHeight(self.coverPhotoView.frame);
    CGFloat coverPhotoOffsetPercent = 0;
    if (self.coverPhotoMimicsNavigationBar) {
        coverPhotoOffset -= CGRectGetMaxY(self.navigationView.frame);
    }
    coverPhotoOffsetPercent = MIN(1, contentOffset.y / coverPhotoOffset);

    if (self.coverPhotoOptions & DBProfileCoverPhotoOptionExtended) {
        CGFloat alpha = 1 - coverPhotoOffsetPercent * 1.10;
        self.profilePictureView.alpha = self.detailsView.alpha = alpha;
        
    } else {
        CGFloat profilePictureScale = MIN(1 - coverPhotoOffsetPercent * 0.3, 1);
        
        CGAffineTransform transform = CGAffineTransformMakeScale(profilePictureScale, profilePictureScale);
        CGFloat profilePictureOffset = self.profilePictureInset.bottom + self.profilePictureInset.top;
        transform = CGAffineTransformTranslate(transform, 0, MAX(profilePictureOffset * coverPhotoOffsetPercent, 0));
        
        self.profilePictureView.transform = transform;
    }
}

- (void)updateTitleViewWithContentOffset:(CGPoint)contentOffset {
    if (!self.coverPhotoMimicsNavigationBar) return;
    CGFloat titleViewOffset = ((CGRectGetHeight(self.coverPhotoView.frame) - CGRectGetMaxY(self.navigationView.frame)) + CGRectGetHeight(self.segmentedControlView.frame));
    
    if (self.coverPhotoOptions & DBProfileCoverPhotoOptionExtended) {
        // FIXME: Adding arbitrary padding to titleViewOffset
    } else {
        CGFloat profilePictureOffset = self.profilePictureInset.top - self.profilePictureInset.bottom;
        titleViewOffset += (CGRectGetHeight(self.profilePictureView.frame) + profilePictureOffset + 30);
    }
    
    CGFloat titleViewOffsetPercent = 1 - contentOffset.y / titleViewOffset;
    
    if (self.view.traitCollection.verticalSizeClass == UIUserInterfaceSizeClassCompact) {
        [self.navigationView.navigationBar setTitleVerticalPositionAdjustment:MAX(titleViewOffset * titleViewOffsetPercent, -4)
                                                                forBarMetrics:UIBarMetricsCompact];
    } else {
        [self.navigationView.navigationBar setTitleVerticalPositionAdjustment:MAX(titleViewOffset * titleViewOffsetPercent, 0)
                                                            forBarMetrics:UIBarMetricsDefault];
    }
}

#pragma mark - Notifications

- (void)applicationDidEnterBackground:(NSNotification *)notification {
    [self.blurredImageCache removeAllObjects];
}

- (void)applicationWillEnterForeground:(NSNotification *)notification {
    UIImage *coverPhoto = self.coverPhotoView.imageView.image;
    if (coverPhoto) {
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            [self fillBlurredImageCacheWithImage:coverPhoto];
        });
    }
}

#pragma mark - Updating Constraints

- (void)updateCoverPhotoViewLayoutConstraints {    
    if (self.coverPhotoViewBottomConstraint &&
        self.coverPhotoViewTopSuperviewConstraint &&
        self.coverPhotoViewTopLayoutGuideConstraint) {
        
        switch (self.view.traitCollection.verticalSizeClass) {
            case UIUserInterfaceSizeClassCompact:
                self.coverPhotoViewBottomConstraint.constant = DBProfileViewControllerNavigationBarHeightCompact;
                break;
            default:
                self.coverPhotoViewBottomConstraint.constant = DBProfileViewControllerNavigationBarHeightRegular;
                break;
        }
        
        if (self.coverPhotoMimicsNavigationBar) {
            [NSLayoutConstraint activateConstraints:@[self.coverPhotoViewBottomConstraint, self.coverPhotoViewTopSuperviewConstraint]];
            [NSLayoutConstraint deactivateConstraints:@[self.coverPhotoViewTopLayoutGuideConstraint]];
        } else {
            [NSLayoutConstraint activateConstraints:@[self.coverPhotoViewTopLayoutGuideConstraint]];
            [NSLayoutConstraint deactivateConstraints:@[self.coverPhotoViewBottomConstraint, self.coverPhotoViewTopSuperviewConstraint]];
        }
    }
}

- (void)updateProfilePictureViewLayoutConstraints {
    if (self.profilePictureViewLeftConstraint && self.profilePictureViewCenterXConstraint) {
        switch (self.profilePictureAlignment) {
            case DBProfilePictureAlignmentLeft:
                [NSLayoutConstraint activateConstraints:@[self.profilePictureViewLeftConstraint]];
                [NSLayoutConstraint deactivateConstraints:@[self.profilePictureViewRightConstraint, self.profilePictureViewCenterXConstraint]];
                break;
            case DBProfilePictureAlignmentRight:
                [NSLayoutConstraint activateConstraints:@[self.profilePictureViewRightConstraint]];
                [NSLayoutConstraint deactivateConstraints:@[self.profilePictureViewLeftConstraint, self.profilePictureViewCenterXConstraint]];
                break;
            case DBProfilePictureAlignmentCenter:
                [NSLayoutConstraint activateConstraints:@[self.profilePictureViewCenterXConstraint]];
                [NSLayoutConstraint deactivateConstraints:@[self.profilePictureViewLeftConstraint, self.profilePictureViewRightConstraint]];
                break;
            default:
                break;
        }
    }
    
    switch (self.profilePictureSize) {
        case DBProfilePictureSizeNormal:
            self.profilePictureViewWidthConstraint.constant = DBProfileViewControllerProfilePictureSizeNormal;
            self.profilePictureViewRightConstraint.constant = CGRectGetWidth(self.view.bounds) - DBProfileViewControllerProfilePictureSizeNormal + self.profilePictureInset.left - self.profilePictureInset.right;
            break;
        case DBProfilePictureSizeLarge:
            self.profilePictureViewWidthConstraint.constant = DBProfileViewControllerProfilePictureSizeLarge;
            self.profilePictureViewRightConstraint.constant = CGRectGetWidth(self.view.bounds) - DBProfileViewControllerProfilePictureSizeLarge + self.profilePictureInset.left - self.profilePictureInset.right;
            break;
        default:
            break;
    }
    
    self.profilePictureViewLeftConstraint.constant = self.profilePictureInset.left - self.profilePictureInset.right;
    self.profilePictureViewTopConstraint.constant = self.profilePictureInset.top - self.profilePictureInset.bottom;
}

#pragma mark - Auto Layout

- (void)configureNavigationViewLayoutConstraints {
    [self.view addConstraint:[NSLayoutConstraint constraintWithItem:self.navigationView attribute:NSLayoutAttributeTop relatedBy:NSLayoutRelationEqual toItem:[self topLayoutGuide] attribute:NSLayoutAttributeBottom multiplier:1 constant:0]];
    [self.view addConstraint:[NSLayoutConstraint constraintWithItem:self.navigationView attribute:NSLayoutAttributeLeft relatedBy:NSLayoutRelationEqual toItem:self.view attribute:NSLayoutAttributeLeft multiplier:1 constant:0]];
    [self.view addConstraint:[NSLayoutConstraint constraintWithItem:self.navigationView attribute:NSLayoutAttributeRight relatedBy:NSLayoutRelationEqual toItem:self.view attribute:NSLayoutAttributeRight multiplier:1 constant:0]];
}

- (void)configureSegmentedControlViewLayoutConstraintsWithScrollView:(UIScrollView *)scrollView  {
    [scrollView addConstraint:[NSLayoutConstraint constraintWithItem:self.segmentedControlView attribute:NSLayoutAttributeLeft relatedBy:NSLayoutRelationEqual toItem:scrollView attribute:NSLayoutAttributeLeft multiplier:1 constant:0]];
    [scrollView addConstraint:[NSLayoutConstraint constraintWithItem:self.segmentedControlView attribute:NSLayoutAttributeWidth relatedBy:NSLayoutRelationEqual toItem:scrollView attribute:NSLayoutAttributeWidth multiplier:1 constant:0]];    
    [scrollView addConstraint:[NSLayoutConstraint constraintWithItem:self.segmentedControlView attribute:NSLayoutAttributeTop relatedBy:NSLayoutRelationGreaterThanOrEqual toItem:self.detailsView attribute:NSLayoutAttributeBottom multiplier:1 constant:0]];
    
    [self.view addConstraint:[NSLayoutConstraint constraintWithItem:self.segmentedControlView attribute:NSLayoutAttributeTop relatedBy:NSLayoutRelationGreaterThanOrEqual toItem:[self topLayoutGuide] attribute:NSLayoutAttributeBottom multiplier:1 constant:0]];
    [self.view addConstraint:[NSLayoutConstraint constraintWithItem:self.segmentedControlView attribute:NSLayoutAttributeTop relatedBy:NSLayoutRelationGreaterThanOrEqual toItem:self.coverPhotoView attribute:NSLayoutAttributeBottom multiplier:1 constant:0]];
}

- (void)configureDetailsViewLayoutConstraintsWithScrollView:(UIScrollView *)scrollView  {
    [scrollView addConstraint:[NSLayoutConstraint constraintWithItem:self.detailsView attribute:NSLayoutAttributeLeft relatedBy:NSLayoutRelationEqual toItem:scrollView attribute:NSLayoutAttributeLeft multiplier:1 constant:0]];
    [scrollView addConstraint:[NSLayoutConstraint constraintWithItem:self.detailsView attribute:NSLayoutAttributeWidth relatedBy:NSLayoutRelationEqual toItem:scrollView attribute:NSLayoutAttributeWidth multiplier:1 constant:0]];
    
    self.detailsViewTopConstraint = [NSLayoutConstraint constraintWithItem:self.detailsView attribute:NSLayoutAttributeTop relatedBy:NSLayoutRelationEqual toItem:scrollView attribute:NSLayoutAttributeTop multiplier:1 constant:0];
    [scrollView addConstraint:self.detailsViewTopConstraint];
}

- (void)configureActivityIndicatorLayoutConstraintsWithScrollView:(UIScrollView *)scrollView {
    [scrollView addConstraint:[NSLayoutConstraint constraintWithItem:self.activityIndicator attribute:NSLayoutAttributeCenterX relatedBy:NSLayoutRelationEqual toItem:self.coverPhotoView attribute:NSLayoutAttributeCenterX multiplier:1 constant:0]];
    [scrollView addConstraint:[NSLayoutConstraint constraintWithItem:self.activityIndicator attribute:NSLayoutAttributeCenterY relatedBy:NSLayoutRelationGreaterThanOrEqual toItem:self.coverPhotoView attribute:NSLayoutAttributeCenterY multiplier:1 constant:0]];
}

- (void)configureCoverPhotoViewLayoutConstraintsWithScrollView:(UIScrollView *)scrollView {
    [scrollView addConstraint:[NSLayoutConstraint constraintWithItem:self.coverPhotoView attribute:NSLayoutAttributeLeft relatedBy:NSLayoutRelationEqual toItem:scrollView attribute:NSLayoutAttributeLeft multiplier:1 constant:0]];
    [scrollView addConstraint:[NSLayoutConstraint constraintWithItem:self.coverPhotoView attribute:NSLayoutAttributeWidth relatedBy:NSLayoutRelationEqual toItem:scrollView attribute:NSLayoutAttributeWidth multiplier:1 constant:0]];
    
    self.coverPhotoViewHeightConstraint = [NSLayoutConstraint constraintWithItem:self.coverPhotoView attribute:NSLayoutAttributeHeight relatedBy:NSLayoutRelationEqual toItem:self.view attribute:NSLayoutAttributeHeight multiplier:self.coverPhotoHeightMultiplier constant:0];
    [self.view addConstraint:self.coverPhotoViewHeightConstraint];
    
    self.coverPhotoViewTopConstraint = [NSLayoutConstraint constraintWithItem:self.coverPhotoView attribute:NSLayoutAttributeTop relatedBy:NSLayoutRelationEqual toItem:scrollView attribute:NSLayoutAttributeTop multiplier:1 constant:0];
    self.coverPhotoViewTopConstraint.priority = UILayoutPriorityDefaultHigh;
    [scrollView addConstraints:@[self.coverPhotoViewTopConstraint]];
    
    self.coverPhotoViewBottomConstraint = [NSLayoutConstraint constraintWithItem:self.coverPhotoView attribute:NSLayoutAttributeBottom relatedBy:NSLayoutRelationGreaterThanOrEqual toItem:self.view attribute:NSLayoutAttributeTop multiplier:1 constant:64];
    [self.view addConstraint:self.coverPhotoViewBottomConstraint];
    
    self.coverPhotoViewTopLayoutGuideConstraint = [NSLayoutConstraint constraintWithItem:self.coverPhotoView attribute:NSLayoutAttributeTop relatedBy:NSLayoutRelationLessThanOrEqual toItem:[self topLayoutGuide] attribute:NSLayoutAttributeBottom multiplier:1 constant:0];
    self.coverPhotoViewTopLayoutGuideConstraint.priority = UILayoutPriorityDefaultHigh + 1;
    [self.view addConstraint:self.coverPhotoViewTopLayoutGuideConstraint];
    
    self.coverPhotoViewTopSuperviewConstraint = [NSLayoutConstraint constraintWithItem:self.coverPhotoView attribute:NSLayoutAttributeTop relatedBy:NSLayoutRelationLessThanOrEqual toItem:self.view attribute:NSLayoutAttributeTop multiplier:1 constant:0];
    self.coverPhotoViewTopSuperviewConstraint.priority = UILayoutPriorityDefaultHigh + 1;
    [self.view addConstraint:self.coverPhotoViewTopSuperviewConstraint];
}

- (void)configureProfilePictureViewLayoutConstraintsWithScrollView:(UIScrollView *)scrollView {
    [scrollView addConstraint:[NSLayoutConstraint constraintWithItem:self.profilePictureView attribute:NSLayoutAttributeHeight relatedBy:NSLayoutRelationEqual toItem:self.profilePictureView attribute:NSLayoutAttributeWidth multiplier:1 constant:0]];
    
    // Customizing size
    self.profilePictureViewWidthConstraint = [NSLayoutConstraint constraintWithItem:self.profilePictureView attribute:NSLayoutAttributeWidth relatedBy:NSLayoutRelationEqual toItem:nil attribute:NSLayoutAttributeNotAnAttribute multiplier:1 constant:DBProfileViewControllerProfilePictureSizeNormal];

    // Customizing horizontal alignment
    self.profilePictureViewLeftConstraint = [NSLayoutConstraint constraintWithItem:self.profilePictureView attribute:NSLayoutAttributeLeft relatedBy:NSLayoutRelationEqual toItem:scrollView attribute:NSLayoutAttributeLeft multiplier:1 constant:0];
    self.profilePictureViewLeftConstraint.priority = UILayoutPriorityDefaultLow;

    self.profilePictureViewRightConstraint = [NSLayoutConstraint constraintWithItem:self.profilePictureView attribute:NSLayoutAttributeLeft relatedBy:NSLayoutRelationEqual toItem:scrollView attribute:NSLayoutAttributeLeft multiplier:1 constant:0];
    self.profilePictureViewRightConstraint.priority = UILayoutPriorityDefaultLow;

    self.profilePictureViewCenterXConstraint = [NSLayoutConstraint constraintWithItem:self.profilePictureView attribute:NSLayoutAttributeCenterX relatedBy:NSLayoutRelationEqual toItem:scrollView attribute:NSLayoutAttributeCenterX multiplier:1 constant:0];
    self.profilePictureViewCenterXConstraint.priority = UILayoutPriorityDefaultLow;

    // Customizing vertical alignment
    self.profilePictureViewTopConstraint = [NSLayoutConstraint constraintWithItem:self.profilePictureView attribute:NSLayoutAttributeTop relatedBy:NSLayoutRelationEqual toItem:self.detailsView attribute:NSLayoutAttributeTop multiplier:1 constant:0];
    
    [scrollView addConstraints:@[self.profilePictureViewWidthConstraint, self.profilePictureViewLeftConstraint, self.profilePictureViewRightConstraint, self.profilePictureViewCenterXConstraint, self.profilePictureViewTopConstraint]];
    
    [NSLayoutConstraint deactivateConstraints:@[self.profilePictureViewLeftConstraint, self.profilePictureViewRightConstraint, self.profilePictureViewCenterXConstraint]];
}

#pragma mark - Blurring

- (UIImage *)blurredImageAt:(CGFloat)percent {
    NSNumber *keyNumber = @(round(percent * 15));
    return [self.blurredImageCache objectForKey:keyNumber];
}

- (void)fillBlurredImageCacheWithImage:(UIImage *)image {
    NSAssert(![NSThread isMainThread], @"`fillBlurredImageCacheWithImage:` should not be called on main thread");
    CGFloat maxBlurRadius = 30;
    [self.blurredImageCache removeAllObjects];
    for (int i = 0; i <= 15; i++) {
        CGFloat radius = maxBlurRadius * i/15;
        [self.blurredImageCache setObject:[DBProfileImageEffects imageByApplyingBlurToImage:image withRadius:radius] forKey:@(i)];
    }
}

@end
