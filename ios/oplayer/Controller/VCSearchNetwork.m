//
//  VCSearchNetwork.m
//  oplayer
//
//  Created by SYALON on 13-12-24.
//
//

#import "VCSearchNetwork.h"
#import "BitsharesClientManager.h"
#import "AppCacheManager.h"
#import "MySearchBar.h"
#import "OrgUtils.h"
#import "UIImage+ImageEffects.h"

@interface VCSearchNetwork ()
{
    ENetworkSearchType          _searchType;
    
    SelectAccountCallback       _callback;
    NSDictionary*               _selectedResult;
    
    BOOL                        _bEnableSectionIndexTitle;
    BOOL                        _bEnableSelectRow;
    
    //  搜索栏
    UITableView*                _allDataTableView;
    NSString*                   _currSearchText;
}

@end

@implementation VCSearchNetwork

-(void)deallocSectionData
{
    _pSectionTitle = nil;
    if (_pSectionHash)
    {
        [_pSectionHash removeAllObjects];
        _pSectionHash = nil;
    }
}

-(void)dealloc
{
    _callback = nil;
    _selectedResult = nil;
    
    _currSearchText = nil;
    [self deallocSectionData];
    if (_allDataTableView){
        _allDataTableView.delegate = nil;
        _allDataTableView = nil;
    }
    if (_searchController){
        if (_searchController.searchBar){
            _searchController.searchBar.delegate = nil;
        }
        _searchController.searchResultsUpdater = nil;
        _searchController.delegate = nil;
    }
    _searchDataArray = nil;
    _array_data = nil;
}

/**
 *  (private) 初始化自定义交易对列表
 */
- (void)reinitCustomMarketList
{
    if (_array_data){
        [_array_data removeAllObjects];
    }else{
        _array_data = [NSMutableArray array];
    }
    id custom_markets = [[AppCacheManager sharedAppCacheManager] get_all_custom_markets];
    if ([custom_markets count] <= 0){
        return;
    }
    NSMutableDictionary* market_hash = [NSMutableDictionary dictionary];
    for (id market in [[ChainObjectManager sharedChainObjectManager] getDefaultMarketInfos]) {
        id base = market[@"base"];
        market_hash[base[@"symbol"]] = base;
    }
    for (id custom_item in [custom_markets allValues]) {
        id base_symbol = custom_item[@"base"];
        id market_base = market_hash[base_symbol];
        //  无效数据（用户添加之后，官方删除了部分市场可能存在该情况。TODO:fowallet 考虑从缓存移除。）
        if (!market_base){
            continue;
        }
        id quote = custom_item[@"quote"];
        [_array_data addObject:@{@"base":market_base, @"quote":quote}];
    }
    //  排序
    [_array_data sortUsingComparator:(^NSComparisonResult(id  _Nonnull obj1, id  _Nonnull obj2) {
        return [obj1[@"quote"][@"symbol"] compare:obj2[@"quote"][@"symbol"]];
    })];
}

- (id)initWithSearchType:(ENetworkSearchType)searchType callback:(SelectAccountCallback)callback
{
    self = [super init];
    if (self) {
        _searchType = searchType;
        
        _callback = callback;
        _selectedResult = nil;
        
        // Custom initialization
        
        //  设置各种属性标记
        switch (_searchType) {
            case enstAccount:   //  搜索帐号：添加我的关注
            {
                _bEnableSelectRow = YES;
                
                _bEnableSectionIndexTitle = NO;
                _pSectionHash = nil;
                _pSectionTitle = nil;
                
                _array_data = [[[[[AppCacheManager sharedAppCacheManager] get_all_fav_accounts] allValues] sortedArrayUsingComparator:(^NSComparisonResult(id  _Nonnull obj1, id  _Nonnull obj2) {
                    return [[obj1 objectForKey:@"name"] compare:[obj2 objectForKey:@"name"]];
                })] mutableCopy];
            }
                break;
            case enstAsset:     //  搜索资产：添加所有市场交易对
            {
                _bEnableSelectRow = NO;
                _bEnableSectionIndexTitle = NO;
                _array_data = nil;
                [self reinitCustomMarketList];
            }
                break;
            default:
                break;
        }
        
        _searchDataArray = [[NSMutableArray alloc] init];
        _currSearchText = nil;
    }
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    // Do any additional setup after loading the view.
    ThemeManager* theme = [ThemeManager sharedThemeManager];
    self.view.backgroundColor = theme.appBackColor;
    
    if (_bEnableSectionIndexTitle)
    {
        NSMutableArray* tempTitle = [NSMutableArray array];
        for (NSDictionary* item in _array_data)
        {
            NSString* pFirstPinyin = [self getFirstLetter:item];
            NSMutableArray* pSectionList = [_pSectionHash objectForKey:pFirstPinyin];
            if (!pSectionList)
            {
                pSectionList = [[NSMutableArray alloc] init];
                [_pSectionHash setValue:pSectionList forKey:pFirstPinyin];
                [tempTitle addObject:pFirstPinyin];
            }
            [pSectionList addObject:item];
        }
        _pSectionTitle = [tempTitle sortedArrayUsingComparator:^NSComparisonResult(id obj1, id obj2) {
            return [obj1 compare:obj2];
        }];
    }
    else
    {
        _pSectionTitle = nil;
    }

    //  搜索框
    _searchController = [[UISearchController alloc] initWithSearchResultsController:nil];
    _searchController.searchBar.delegate = self;
    switch (_searchType) {
        case enstAccount:
            _searchController.searchBar.placeholder = NSLocalizedString(@"kSearchPlaceholderAccount", @"请输入有效的 Bitshares 帐号名");
            break;
        case enstAsset:
            _searchController.searchBar.placeholder = NSLocalizedString(@"kSearchPlaceholderAsset", @"点击搜索新资产");
            break;
        default:
            break;
    }
    //  [兼容性] REMARK：iOS13 如果用 barTintColor 设置背景色会存在黑边。直接改成 setBackgroundImage 。
    [_searchController.searchBar setBackgroundImage:[UIImage imageWithColor:theme.appBackColor]];
    _searchController.searchBar.tintColor = theme.textColorHighlight;
    [_searchController.searchBar sizeToFit];
    _searchController.searchResultsUpdater = self;
    _searchController.delegate = self;
    _searchController.dimsBackgroundDuringPresentation = NO;
    _searchController.hidesNavigationBarDuringPresentation = YES;
    _searchController.searchBar.backgroundColor = theme.appBackColor;
    [self.view addSubview:_searchController.searchBar];
    self.definesPresentationContext = YES;  //  REMARK：解决SearchController偏移问题
        
    //  [兼容性] REMARK：iOS13 采用这种方法获取 TF 对象。直接 KVC 会崩溃。设置搜索框文字颜色和占位符颜色。
    UITextField* tf = (UITextField*)[_searchController.searchBar findSubview:[UITextField class] resursion:YES];
    tf.textColor = theme.textColorMain;
    
    //  列表
    _allDataTableView = [[UITableView alloc] initWithFrame:[self rectWithoutNavi] style:UITableViewStylePlain];
    _allDataTableView.delegate = self;
    _allDataTableView.dataSource = self;
    _allDataTableView.backgroundColor = [UIColor clearColor];
    _allDataTableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    //  [兼容性] REMARK：iOS13 下拉背景色异常，故封装到view中。
    UIView* containView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, [self heightForStatusAndNaviBar])];
    containView.backgroundColor = theme.appBackColor;
    [containView addSubview:_searchController.searchBar];
    _allDataTableView.tableHeaderView = containView;
    [self.view addSubview:_allDataTableView];
    _allDataTableView.tintColor = theme.tintColor;
}

- (void)viewWillLayoutSubviews
{
    [super viewWillLayoutSubviews];
    
    //  [兼容性] REMARK：iOS13 BUG，attributedPlaceholder 在 viewDidLoad 中设置无效，改到这里修改。
    ThemeManager* theme = [ThemeManager sharedThemeManager];
    UITextField* tf = (UITextField*)[_searchController.searchBar findSubview:[UITextField class] resursion:YES];
    if (tf) {
        tf.attributedPlaceholder = [[NSAttributedString alloc] initWithString:_searchController.searchBar.placeholder
                                                                         attributes:@{NSForegroundColorAttributeName:theme.textColorGray,
                                                                                      NSFontAttributeName:[UIFont systemFontOfSize:17]}];
    }
    
    //  [兼容性] REMARK：iOS13 取消按钮文字用 KVC 方式崩溃。采用以下方法设置并且不能放在 viewDidLoad 中进行设置。
    Class klass = NSClassFromString(@"UINavigationButton");
    if (klass) {
        [_searchController.searchBar iterateSubview:^BOOL(UIView *view) {
            if ([view isKindOfClass:klass]) {
                [(UIButton*)view setTitle:NSLocalizedString(@"kBtnCancel", @"取消") forState:UIControlStateNormal];
                return YES;
            }
            return NO;
        }];
    }
}

- (void)viewWillDisappear:(BOOL)animated
{
    [super viewWillDisappear:animated];
    //  选择帐号回调
    if (_callback){
        id result = _selectedResult ? [_selectedResult copy] : nil;
        [self delay:^{
            _callback(result);
        }];
    }
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

#pragma mark- TableView delegate method

/**
    (private) 是否显示搜索结果，否则显示默认列表数据。
 */
- (BOOL)_showSearchResultData
{
    return _searchController.active && _currSearchText && ![_currSearchText isEqualToString:@""];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    if ([self _showSearchResultData]) {
        return 1;
    }
    if (_bEnableSectionIndexTitle)
        return [_pSectionTitle count];
    else
        return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    if ([self _showSearchResultData])
        return [_searchDataArray count];
    
    if (_bEnableSectionIndexTitle){
        NSArray* pSection = [_pSectionHash objectForKey:[_pSectionTitle objectAtIndex:section]];
        return [pSection count];
    }else{
        return [_array_data count];
    }
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section
{
    return 22.0f;
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section
{
    UIView* myView = [[UIView alloc] init];
    myView.backgroundColor = [ThemeManager sharedThemeManager].appBackColor;
    UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(10, 0, 300, 22)];
    titleLabel.textColor = [ThemeManager sharedThemeManager].textColorHighlight;
    titleLabel.backgroundColor = [UIColor clearColor];
    titleLabel.font = [UIFont boldSystemFontOfSize:13];
    if ([self _showSearchResultData])
        titleLabel.text = NSLocalizedString(@"search_result", @"搜索结果");
    else if (_bEnableSectionIndexTitle)
        titleLabel.text = [_pSectionTitle objectAtIndex:section];
    else
    {
        switch (_searchType) {
            case enstAccount:
                titleLabel.text = [NSString stringWithFormat:NSLocalizedString(@"kSearchTipsMyFavAccount", @"我的关注(%@人)"), @([_array_data count])];
                break;
            case enstAsset:
                titleLabel.text = [NSString stringWithFormat:NSLocalizedString(@"kSearchTipsMyCustomPairs", @"我的交易对(%@个)"), @([_array_data count])];
                break;
            default:
                break;
        }
    }
    [myView addSubview:titleLabel];
    return myView;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    static NSString *identify = @"vcselectitemfromlist";
    UITableViewCellBase* cell = (UITableViewCellBase *)[tableView dequeueReusableCellWithIdentifier:identify];
    if (!cell)
    {
        cell = [[UITableViewCellBase alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:identify];
        cell.accessoryType = UITableViewCellAccessoryNone;
        cell.backgroundColor = [UIColor clearColor];
        if (_bEnableSelectRow){
            cell.selectionStyle = UITableViewCellSelectionStyleBlue;
        }else{
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
        }
    }
    if ([self _showSearchResultData])
    {
        [self drawTableViewCell:cell data:[_searchDataArray objectAtIndex:indexPath.row] section:indexPath.section row:indexPath.row];
    }
    else if (_bEnableSectionIndexTitle)
    {
        NSArray* pSection = [_pSectionHash objectForKey:[_pSectionTitle objectAtIndex:indexPath.section]];
        [self drawTableViewCell:cell data:[pSection objectAtIndex:indexPath.row] section:indexPath.section row:indexPath.row];
    }
    else
    {
        [self drawTableViewCell:cell data:[_array_data objectAtIndex:indexPath.row] section:indexPath.section row:indexPath.row];
    }
    return cell;
    
}

-(void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    if (_bEnableSelectRow)
    {
        [tableView deselectRowAtIndexPath:indexPath animated:YES];
        
        [[IntervalManager sharedIntervalManager] callBodyWithFixedInterval:tableView body:^{
            NSDictionary* pData = nil;
            if ([self _showSearchResultData])
            {
                pData = [_searchDataArray objectAtIndex:indexPath.row];
            }
            else if (_bEnableSectionIndexTitle)
            {
                NSArray* pSection = [_pSectionHash objectForKey:[_pSectionTitle objectAtIndex:indexPath.section]];
                pData = [pSection objectAtIndex:indexPath.row];
            }
            else
            {
                pData = [_array_data objectAtIndex:indexPath.row];
            }
            
            [self save_result:pData];
            
            [self.navigationController popViewControllerAnimated:YES];
        }];
    }
}

#pragma mark- TableView Index delegate method

- (NSArray *)sectionIndexTitlesForTableView:(UITableView *)tableView
{
    if ([self _showSearchResultData])
        return nil;
    
    if (_bEnableSectionIndexTitle)
        return _pSectionTitle;
    else
        return nil;
}

#pragma mark - search bar & searchdisplaycontroller

- (void)didPresentSearchController:(UISearchController *)searchController
{
    //  [兼容性] REMARK：iOS13 搜索框取消按钮修改多语言文字之后这里重新设置下大小。
    Class klass = NSClassFromString(@"UINavigationButton");
    if (klass) {
        [_searchController.searchBar iterateSubview:^BOOL(UIView *view) {
            if ([view isKindOfClass:klass]) {
                UIButton* btn = (UIButton*)view;
                CGSize size1 = [UITableViewCellBase auxSizeWithText:btn.titleLabel.text
                                                               font:btn.titleLabel.font
                                                            maxsize:CGSizeMake(self.view.bounds.size.width, 9999)];
                CGRect frame = btn.frame;
                btn.frame = CGRectMake(frame.origin.x, frame.origin.y, size1.width, frame.size.height);
                return YES;
            }
            return NO;
        }];
    }
}

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController
{
    [_allDataTableView reloadData];
}

- (BOOL)isSearchMatched:(NSString*)target match:(NSString*)match
{
    //  TODO:fowallet 匹配方法待考虑，全相等，还是startWith？
    return [target rangeOfString:match].location == 0;
}

- (void)processSearchResult:(id)data
{
    [_searchDataArray removeAllObjects];
    
    NSString* sortKey = nil;
    switch (_searchType) {
        case enstAccount:   //  帐号信息
        {
            sortKey = @"name";
            for (id d in data) {
                if ([self isSearchMatched:d[0] match:_currSearchText]){
                    [_searchDataArray addObject:@{sortKey:d[0], @"id":d[1]}];
                }
            }
            //  按照帐号名字长度升序排列（即匹配度高的排在前面） 比如 搜索：freedom16，那么 freedom168就排在freedom1613前面。
            if ([_searchDataArray count] > 0){
                [_searchDataArray sortUsingComparator:^NSComparisonResult(id  _Nonnull obj1, id  _Nonnull obj2) {
                    return [[obj1 objectForKey:sortKey] length] > [[obj2 objectForKey:sortKey] length];
                }];
            }
        }
            break;
        case enstAsset:     //  资产信息
        {
            id base_markets = [[ChainObjectManager sharedChainObjectManager] getDefaultMarketInfos];
            sortKey = @"symbol";
            for (id d in data) {
                if ([self isSearchMatched:[d objectForKey:sortKey] match:_currSearchText]){
                    for (id market in base_markets) {
                        id base = [market objectForKey:@"base"];
                        //  REMARK：略过 base 和 quote 相同的交易对：CNY/CNY USD/USD X4T/X4T
                        if ([[d objectForKey:@"symbol"] isEqualToString:[base objectForKey:@"symbol"]]){
                            continue;
                        }
                        [_searchDataArray addObject:@{@"quote":d, @"base":base}];
                    }
                }
            }
            
            //  按照帐号名字长度升序排列（即匹配度高的排在前面） 比如 搜索：freedom16，那么 freedom168就排在freedom1613前面。
            if ([_searchDataArray count] > 0){
                [_searchDataArray sortUsingComparator:^NSComparisonResult(id  _Nonnull obj1, id  _Nonnull obj2) {
                    return [[[obj1 objectForKey:@"quote"] objectForKey:sortKey] length] > [[[obj2 objectForKey:@"quote"] objectForKey:sortKey] length];
                }];
            }
            
        }
            break;
        default:
            break;
    }
    
    //  更新搜索结果后刷新
    [_allDataTableView reloadData];
}

- (BOOL)searchBarShouldBeginEditing:(UISearchBar *)searchBar
{
    [_searchDataArray removeAllObjects];
    _currSearchText = nil;
    return YES;
}

- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)searchText   // called when text changes (including clear)
{
    NSString* api_string = nil;
    
    switch (_searchType) {
        case enstAccount:
        {
            api_string = @"lookup_accounts";
            searchText = [searchText lowercaseString];  //  帐号搜索全小写字母
        }
            break;
        case enstAsset:
        {
            api_string = @"list_assets";
            searchText = [searchText uppercaseString];  //  资产搜索全大写字母
        }
            break;
        default:
            assert(NO);
            break;
    }
    
    _currSearchText = [searchText copy];
    NSLog(@"searchText %@", searchText);
    
    GrapheneApi* api = [[GrapheneConnectionManager sharedGrapheneConnectionManager] any_connection].api_db;
    
    //  这里面引用的变量必须是 weak 的，不然该 vc 没法释放。 TODO:api catch
    __weak id this = self;
    [[[api exec:api_string params:@[searchText, @20]] then:(^id(id data) {
        if (this){
            if ([_currSearchText isEqualToString:searchText]){
                [this processSearchResult:data];
            }else{
                NSLog(@"网络延迟太大，搜索字符串已经变更，忽略当前搜索结果。%@ -> %@", searchText, _currSearchText);
            }
        }else{
            NSLog(@"search finish & vc have released...");
        }
        return nil;
    })] catch:(^id(id error) {
        //  TODO:fowallet 忽略异常？
        return nil;
    })];
}

#pragma mark- virtual methods

/**
 *  获取首字母（用于列表右边索引栏）
 */
- (NSString*)getFirstLetter:(NSDictionary*)linedata
{
    return [[[linedata objectForKey:@"py_full"] substringToIndex:1] uppercaseString];
}

/**
 *  保存结果
 */
- (void)save_result:(NSDictionary*)data
{
    _selectedResult = data;
}

/**
 *  资产 - 添加/删除自定义市场开关
 */
- (void)onSwitchAction:(UISwitch*)sender
{
    UITableView* tableView = nil;
    UIView* it = sender;
    while (it.superview)
    {
        if ([it.superview isKindOfClass:[UITableView class]])
        {
            tableView = (UITableView*)it.superview;
            break;
        }
        it = it.superview;
    }
    //  没找到 UITableView（不应该出现）
    if (!tableView){
        return;
    }
    
    BOOL needReloadMainTableview = NO;
    id linedata;
    if ([self _showSearchResultData])
    {
        //  REMARK：在搜索结果界面点击开关按钮，此时需要刷新非搜索状态下的 maintableview。
        needReloadMainTableview = YES;
        linedata = [_searchDataArray objectAtIndex:sender.tag];
    }
    else
    {
        linedata = [_array_data objectAtIndex:sender.tag];
    }
    
    AppCacheManager* pAppCache = [AppCacheManager sharedAppCacheManager];
    if (sender.on){
        NSInteger max_custom_pair_num = [[[ChainObjectManager sharedChainObjectManager] getDefaultParameters][@"max_custom_pair_num"] integerValue];
        if ([[pAppCache get_all_custom_markets] count] >= max_custom_pair_num){
            //  关闭switch&刷新tableview（不然UISwitch样式不会更新）
            sender.on = NO;
            [tableView reloadData];
            [OrgUtils makeToast:[NSString stringWithFormat:NSLocalizedString(@"kSearchTipsMaxCustomParisNumber", @"最多只能自定义 %@ 个交易对。"), @(max_custom_pair_num)]];
            return;
        }
        id quote = [linedata objectForKey:@"quote"];
        id base = [linedata objectForKey:@"base"];
        [[pAppCache set_custom_markets:quote
                                  base:[base objectForKey:@"symbol"]] saveCustomMarketsToFile];
        //  [统计]
        [OrgUtils logEvents:@"event_custommarket_add"
                       params:@{@"base":[base objectForKey:@"symbol"], @"quote":[quote objectForKey:@"symbol"]}];
    }else{
        id quote = [linedata objectForKey:@"quote"];
        id base = [linedata objectForKey:@"base"];
        [[pAppCache remove_custom_markets:[quote objectForKey:@"symbol"]
                                     base:[base objectForKey:@"symbol"]] saveCustomMarketsToFile];
        //  [统计]
        [OrgUtils logEvents:@"event_custommarket_remove"
                       params:@{@"base":[base objectForKey:@"symbol"], @"quote":[quote objectForKey:@"symbol"]}];
    }
    
    //  刷新 mainTableView
    if (needReloadMainTableview){
        //  REMARK：简单重新初始化列表即可，不用单独考虑 移除 or 添加。
        [self reinitCustomMarketList];
        [_allDataTableView reloadData];
    }
    
    //  标记：自定义交易对发生变化，市场列表需要更新。
    [TempManager sharedTempManager].customMarketDirty = YES;
}

/**
 *  设置cell的显示内容
 */
- (void)drawTableViewCell:(UITableViewCell*)cell data:(NSDictionary*)linedata section:(NSInteger)section row:(NSInteger)row
{
    switch (_searchType) {
        case enstAccount:
        {
            cell.textLabel.text = [linedata objectForKey:@"name"];
            cell.textLabel.textColor = [ThemeManager sharedThemeManager].textColorMain;
            cell.detailTextLabel.text = [NSString stringWithFormat:@"#%@", [[[linedata objectForKey:@"id"] componentsSeparatedByString:@"."] lastObject]];
            cell.detailTextLabel.textColor = [ThemeManager sharedThemeManager].textColorNormal;
        }
            break;
        case enstAsset:
        {
            id quote = [linedata objectForKey:@"quote"];
            id base = [linedata objectForKey:@"base"];
            
            cell.textLabel.text = [NSString stringWithFormat:@"%@/%@", [quote objectForKey:@"symbol"], [base objectForKey:@"name"]];
            
            if ([[ChainObjectManager sharedChainObjectManager] isDefaultPair:quote base:base]){
                cell.textLabel.textColor = [ThemeManager sharedThemeManager].textColorNormal;
                cell.detailTextLabel.text = NSLocalizedString(@"kSearchTipsForbidden", @"不可更改");
                cell.detailTextLabel.textColor = [ThemeManager sharedThemeManager].textColorNormal;
                cell.accessoryView = nil;
            }else{
                cell.textLabel.textColor = [ThemeManager sharedThemeManager].textColorMain;
                cell.detailTextLabel.text = @"";
                
                id quote_symbol = [quote objectForKey:@"symbol"];
                id base_symbol = [base objectForKey:@"symbol"];
                
                UISwitch* pSwitch = [[UISwitch alloc] initWithFrame:CGRectZero];
                pSwitch.tintColor = [ThemeManager sharedThemeManager].textColorGray;        //  边框颜色
                pSwitch.thumbTintColor = [ThemeManager sharedThemeManager].textColorGray;   //  按钮颜色
                pSwitch.onTintColor = [ThemeManager sharedThemeManager].textColorHighlight; //  开启时颜色
                pSwitch.tag = row;
                pSwitch.on = [[AppCacheManager sharedAppCacheManager] is_custom_market:quote_symbol base:base_symbol];
                [pSwitch addTarget:self action:@selector(onSwitchAction:) forControlEvents:UIControlEventValueChanged];
                cell.accessoryView = pSwitch;
            }
        }
            break;
        default:
            break;
    }
}

@end
