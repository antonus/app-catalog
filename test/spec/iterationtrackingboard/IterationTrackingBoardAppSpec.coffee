Ext = window.Ext4 || window.Ext

Ext.require [
  'Rally.apps.iterationtrackingboard.IterationTrackingBoardApp'
  'Rally.ui.gridboard.GridBoard'
  'Rally.util.DateTime'
  'Rally.app.Context',
  'Rally.domain.Subscription'
]

describe 'Rally.apps.iterationtrackingboard.IterationTrackingBoardApp', ->

  helpers
    createApp: (config)->
      @stub(Rally.apps.iterationtrackingboard.StatsBanner::, 'getHeight').returns 0
      now = new Date(1384305300 * 1000);
      tomorrow = Rally.util.DateTime.add(now, 'day', 1)
      nextDay = Rally.util.DateTime.add(tomorrow, 'day', 1)
      dayAfter = Rally.util.DateTime.add(nextDay, 'day', 1)
      @iterationData = [
        {Name:'Iteration 1', _ref:'/iteration/0', StartDate: now, EndDate: tomorrow}
        {Name:'Iteration 2', _ref:'/iteration/2', StartDate: nextDay, EndDate: dayAfter}
      ]

      @IterationModel = Rally.test.mock.data.WsapiModelFactory.getIterationModel()
      @iterationRecord = new @IterationModel @iterationData[0]

      @app = Ext.create('Rally.apps.iterationtrackingboard.IterationTrackingBoardApp', Ext.apply(
        context: Ext.create('Rally.app.Context',
          initialValues:
            timebox: Ext.create 'Rally.app.TimeboxScope', record: @iterationRecord
            project:
              _ref: @projectRef
            workspace:
              WorkspaceConfiguration:
                DragDropRankingEnabled: true
        ),
        renderTo: 'testDiv'
        height: 400
      , config))

      @waitForComponentReady(@app)

    getIterationFilter: ->
      iteration = @iterationData[0]

      [
        { property: 'Iteration.Name', operator: '=', value: iteration.Name }
        { property: "Iteration.StartDate", operator: '=', value: Rally.util.DateTime.toIsoString(iteration.StartDate) }
        { property: "Iteration.EndDate", operator: '=', value: Rally.util.DateTime.toIsoString(iteration.EndDate) }
      ]

    stubRequests: ->
      @ajax.whenQueryingAllowedValues('userstory', 'ScheduleState').respondWith(["Defined", "In-Progress", "Completed", "Accepted"]);

      @ajax.whenQuerying('artifact').respondWith [{
        RevisionHistory: {
          _ref: '/revisionhistory/1'
        }
      }]

    toggleToBoard: ->
      @app.gridboard.setToggleState('board')

    toggleToGrid: ->
      @app.gridboard.setToggleState('grid')

    stubFeatureToggle: (toggles) ->
      stub = @stub(Rally.app.Context.prototype, 'isFeatureEnabled');
      stub.withArgs(toggle).returns(true) for toggle in toggles
      stub

  beforeEach ->
    @defaultToggleState = Rally.ui.gridboard.GridBoard.prototype.toggleState
    Rally.ui.gridboard.GridBoard.prototype.toggleState = 'board' # tests assume board is default view

    @ajax.whenReading('project').respondWith {
      TeamMembers: []
      Editors: []
    }

    @stubRequests()

    @tooltipHelper = new Helpers.TooltipHelper this

  afterEach ->
    @app?.destroy()
    Rally.ui.gridboard.GridBoard.prototype.toggleState = @defaultToggleState

  it 'resets view on scope change', ->
    @createApp().then =>
      removeSpy = @spy(@app, 'remove')

      newScope = Ext.create('Rally.app.TimeboxScope',
        record: new @IterationModel @iterationData[1]
      )

      @app.onTimeboxScopeChange newScope

      expect(removeSpy).toHaveBeenCalledTwice()
      expect(removeSpy).toHaveBeenCalledWith 'statsBanner'
      expect(removeSpy).toHaveBeenCalledWith 'gridBoard'

      expect(@app.down('#gridBoard')).toBeDefined()
      expect(@app.down('#statsBanner')).toBeDefined()

  it 'should add the stats banner', ->
    @createApp().then =>
      statsBanner = @app.down '#statsBanner'
      expect(statsBanner).not.toBeNull()
      expect(statsBanner.getContext()).toBe @app.getContext()

  it 'should resize the grid board when stats banner is toggled', ->
    @createApp().then =>
      statsBanner = @app.down '#statsBanner'
      setHeightSpy = @spy @app.down('rallygridboard'), 'setHeight'
      statsBanner.setHeight 40
      @waitForCallback(setHeightSpy)

  it 'fires contentupdated event after board load', ->
    contentUpdatedHandlerStub = @stub()
    @createApp(
      listeners:
        contentupdated: contentUpdatedHandlerStub
    ).then =>
      contentUpdatedHandlerStub.reset()
      @app.gridboard.fireEvent('load')

      expect(contentUpdatedHandlerStub).toHaveBeenCalledOnce()

  it 'should include PortfolioItem in columnConfig.additionalFetchFields', ->
    @createApp().then =>
      expect(@app.gridboard.getGridOrBoard().columnConfig.additionalFetchFields).toContain 'PortfolioItem'

  it 'should use shallow fetch for the cardboard', ->
    @createApp().then =>
      expect(@app.gridboard.getGridOrBoard().storeConfig.useShallowFetch).toBe(true)

  it 'should have a default card fields setting', ->
    @createApp().then =>
      expect(@app.down('rallygridboard').getGridOrBoard().columnConfig.fields).toEqual ['Parent', 'Tasks', 'Defects', 'Discussion', 'PlanEstimate', 'Iteration']

  it 'should have use the cardFields setting if available', ->
    @createApp(
      settings:
        cardFields: 'HelloKitty'
    ).then =>
      expect(@app.down('rallygridboard').getGridOrBoard().columnConfig.fields).toEqual ['HelloKitty']

  it 'should show the field picker in board mode', ->
    @createApp().then =>
      @toggleToBoard()
      expect(@app.down('#fieldpickerbtn').isVisible()).toBe true

  it 'should enable bulk edit when toggled on', ->
    @stubFeatureToggle ['BETA_TRACKING_EXPERIENCE']
    @createApp().then =>
      @toggleToGrid()
      expect(@app.down('#gridBoard').getGridOrBoard().enableBulkEdit).toBe true

  it 'should filter the grid to the currently selected iteration', ->
    requestStub = @stubRequests()

    @createApp().then =>
      @toggleToGrid()

      expect(requestStub).toBeWsapiRequestWith filters: @getIterationFilter()

  it 'should filter the board to the currently selected iteration', ->
    requests = @stubRequests()

    @createApp().then =>
      @toggleToBoard()

      expect(request).toBeWsapiRequestWith(filters: @getIterationFilter()) for request in requests

  it 'should show a treegrid when treegrid toggled on', ->
    @createApp().then =>
      @toggleToGrid()
      expect(@app.down('rallytreegrid')).not.toBeNull()
      expect(@app.down('rallygrid')).toBeNull()

  describe '#_getGridColumns', ->
    helpers
      _getDefaultCols: ->
        ['FormattedID', 'Name', 'ScheduleState', 'Blocked', 'PlanEstimate', 'TaskStatus', 'TaskEstimateTotal', 'TaskRemainingTotal', 'Owner', 'DefectStatus', 'Discussion']

    it 'returns the default columns with the FormattedID removed when given no input', ->
      @createApp().then =>
        cols = @app._getGridColumns()
        expectedColumns = _.remove(@_getDefaultCols(), (col) ->
          col != 'FormattedID'
        )

        expect(cols).toEqual expectedColumns

    it 'returns the input columns with the FormattedID removed', ->
      @createApp().then =>
        cols = @app._getGridColumns(['used1', 'used2', 'FormattedID'])

        expect(cols).toEqual ['used1', 'used2']

    it 'enables the summary row on the treegrid when the toggle is on', ->
      @createApp().then =>
        @toggleToGrid()
        expect(@app.down('#gridBoard').getGridOrBoard().showSummary).toBe true

  describe 'tree grid model types', ->
    it 'should include test sets', ->
      @createApp().then =>
        @toggleToGrid()
        expect(@app.down('rallytreegrid').getStore().parentTypes).toContain 'testset'

  describe 'toggle grid/board cls to ensure overflow-y gets set for fixed header plugin', ->
    it 'should add board-toggled class to app on initial load in board view', ->
      @stub(Rally.ui.gridboard.GridBoard::, 'toggleState', 'board')
      @createApp().then =>
        expect(@app.getEl().dom.className).toContain 'board-toggled'

    it 'should add board-toggled class to app when toggled to board view', ->
      @createApp().then =>
        @toggleToBoard()
        expect(@app.getEl().dom.className).toContain 'board-toggled'

    it 'should add grid-toggled class to app when toggled to grid view', ->
      @createApp().then =>
        @toggleToGrid()
        expect(@app.getEl().dom.className).toContain 'grid-toggled'

  describe "summary units", ->
    helpers
      createAppWithWorkspaceConfiguration: (workspaceConfig) ->
        context = Ext.create('Rally.app.Context',
          initialValues:
            timebox: Ext.create 'Rally.app.TimeboxScope', record: @mom.getRecord('iteration')
            project:
              _ref: @projectRef
            workspace:
              WorkspaceConfiguration: workspaceConfig

        )
        @createApp({ context }).then =>
          @toggleToGrid()

      getSummaryColumns: ->
        @app.down('rallytreegrid').summaryColumns

    it "should specify the summary columns", ->
      @createAppWithWorkspaceConfiguration(TaskUnitName: 'dogecoins').then =>
        summaryColumns = @getSummaryColumns()
        expect(summaryColumns.length).toBe(3)
        expect(summaryColumns[0].field).toBe('PlanEstimate')
        expect(summaryColumns[0].type).toBe('sum')
        expect(summaryColumns[1].field).toBe('TaskEstimateTotal')
        expect(summaryColumns[1].type).toBe('sum')
        expect(summaryColumns[2].field).toBe('TaskRemainingTotal')
        expect(summaryColumns[2].type).toBe('sum')

    it "should use the workspace's task unit name", ->
      @createAppWithWorkspaceConfiguration(TaskUnitName: 'dogecoins').then =>
        summaryColumns = @getSummaryColumns()
        expect(summaryColumns[1].units).toBe('dogecoins')
        expect(summaryColumns[2].units).toBe('dogecoins')

    it "should use the workspace's iteration estimate unit name", ->
      workspaceConfig =
        IterationEstimateUnitName: 'shebas'
        ReleaseEstimateUnitName: 'kitties'

      @createAppWithWorkspaceConfiguration(workspaceConfig).then =>
        summaryColumns = @getSummaryColumns()
        expect(summaryColumns[0].units).toBe('shebas')

  describe 'sizing', ->
    it 'should set an initial gridboard height', ->
      @createApp().then =>
        expect(@app.down('rallygridboard').getHeight()).toBe @app.getAvailableGridBoardHeight()

    it 'should update the grid or board height', ->
      @createApp().then =>
        gridBoard = @app.down 'rallygridboard'
        setHeightSpy = @spy gridBoard, 'setHeight'
        currentHeight = gridBoard.getHeight()
        @app.setHeight @app.getHeight() + 10
        @waitForCallback(setHeightSpy).then =>
          expect(gridBoard.getHeight()).toBe currentHeight + 10

  describe 'custom filter popover toggle', ->

    beforeEach ->
      @featureEnabledStub = @stub(Rally.app.Context.prototype, 'isFeatureEnabled')
      @featureEnabledStub.withArgs('BETA_TRACKING_EXPERIENCE').returns true

    it 'uses the CustomFilter popover if the USE_CUSTOM_FILTER_POPOVER_ON_ITERATION_TRACKING_APP toggle is enabled', ->
      @featureEnabledStub.withArgs('USE_CUSTOM_FILTER_POPOVER_ON_ITERATION_TRACKING_APP').returns(true)
      @createApp().then =>
        @click(id: @app.down('rallyfilterbutton').getId()).then ->
          popover = Ext.ComponentQuery.query('rallycustomfilterpopover')[0]
          expect(popover).toBeDefined()

    it 'does not use the CustomFilter popover if the USE_CUSTOM_FILTER_POPOVER_ON_ITERATION_TRACKING_APP toggle is disabled', ->
      @featureEnabledStub.withArgs('USE_CUSTOM_FILTER_POPOVER_ON_ITERATION_TRACKING_APP').returns(false)
      @createApp().then =>
        @click(id: @app.down('rallyfilterbutton').getId()).then ->
          popover = Ext.ComponentQuery.query('rallyfilterpopover')[0]
          expect(popover).toBeDefined()