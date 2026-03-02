local addonName = ...

FrostedsTaskListDB = FrostedsTaskListDB or {}

-- =========================================================
-- Defaults / DB upgrade
-- =========================================================
local function ApplyDefaults()
  FrostedsTaskListDB.day       = FrostedsTaskListDB.day       or {}
  FrostedsTaskListDB.week      = FrostedsTaskListDB.week      or {}
  FrostedsTaskListDB.instances = FrostedsTaskListDB.instances or {}
  FrostedsTaskListDB.misc      = FrostedsTaskListDB.misc      or {}

  FrostedsTaskListDB.activeTab = FrostedsTaskListDB.activeTab or "day"

  FrostedsTaskListDB.window = FrostedsTaskListDB.window or {}
  FrostedsTaskListDB.window.width  = math.max(860, FrostedsTaskListDB.window.width  or 880)
  FrostedsTaskListDB.window.height = math.max(470, FrostedsTaskListDB.window.height or 520)

  FrostedsTaskListDB.lastDailyKey  = FrostedsTaskListDB.lastDailyKey
  FrostedsTaskListDB.lastWeeklyKey = FrostedsTaskListDB.lastWeeklyKey

  FrostedsTaskListDB.shown = FrostedsTaskListDB.shown or false

  FrostedsTaskListDB.collapsedCategories = FrostedsTaskListDB.collapsedCategories or {
    day = {}, week = {}, instances = {}, misc = {}
  }

  FrostedsTaskListDB.filters = FrostedsTaskListDB.filters or {
    day       = { search = "", hideDone = false, hasNotes = false, pri = { [0]=true, [1]=true, [2]=true, [3]=true } },
    week      = { search = "", hideDone = false, hasNotes = false, pri = { [0]=true, [1]=true, [2]=true, [3]=true } },
    instances = { search = "", hideDone = false, hasNotes = false, pri = { [0]=true, [1]=true, [2]=true, [3]=true } },
    misc      = { search = "", hideDone = false, hasNotes = false, pri = { [0]=true, [1]=true, [2]=true, [3]=true } },
  }
end

ApplyDefaults()

-- =========================================================
-- Reset schedule (UTC-based)
-- NA daily reset: 15:00 UTC
-- NA weekly reset: Tuesday 15:00 UTC
-- =========================================================
local RESET_DAILY_H_UTC = 15
local RESET_DAILY_M_UTC = 0

local RESET_WEEKLY_WDAY_UTC = 2 -- date("!%w"): 0=Sun..6=Sat
local RESET_WEEKLY_H_UTC = 15
local RESET_WEEKLY_M_UTC = 0

local function DailyResetKeyUTC(now)
  now = now or time()
  local h = tonumber(date("!%H", now)) or 0
  local m = tonumber(date("!%M", now)) or 0

  local t = now
  if (h < RESET_DAILY_H_UTC) or (h == RESET_DAILY_H_UTC and m < RESET_DAILY_M_UTC) then
    t = now - 86400
  end
  return date("!%Y-%m-%d", t)
end

local function WeeklyResetKeyUTC(now)
  now = now or time()
  local w = tonumber(date("!%w", now)) or 0
  local h = tonumber(date("!%H", now)) or 0
  local m = tonumber(date("!%M", now)) or 0

  local daysSince = (w - RESET_WEEKLY_WDAY_UTC) % 7
  if daysSince == 0 and ((h < RESET_WEEKLY_H_UTC) or (h == RESET_WEEKLY_H_UTC and m < RESET_WEEKLY_M_UTC)) then
    daysSince = 7
  end

  local t = now - (daysSince * 86400)
  return date("!%Y-%m-%d", t)
end

-- Reset behavior: ONLY clear checkboxes (done=false), keep everything else
local function ClearCompletion(list)
  if type(list) ~= "table" then return end
  for i = 1, #list do
    local task = list[i]
    if type(task) == "table" then
      task.done = false
    end
  end
end

local function MaybeResetLists()
  local now = time()
  local changed = false

  local dKey = DailyResetKeyUTC(now)
  if FrostedsTaskListDB.lastDailyKey ~= dKey then
    FrostedsTaskListDB.day = FrostedsTaskListDB.day or {}
    ClearCompletion(FrostedsTaskListDB.day)
    FrostedsTaskListDB.lastDailyKey = dKey
    changed = true
  end

  local wKey = WeeklyResetKeyUTC(now)
  if FrostedsTaskListDB.lastWeeklyKey ~= wKey then
    FrostedsTaskListDB.week = FrostedsTaskListDB.week or {}
    ClearCompletion(FrostedsTaskListDB.week)
    FrostedsTaskListDB.lastWeeklyKey = wKey
    changed = true
  end

  return changed
end

-- =========================================================
-- Countdown helpers
-- =========================================================
local function GetUTCSecsOfDay(now)
  now = now or time()
  local h = tonumber(date("!%H", now)) or 0
  local m = tonumber(date("!%M", now)) or 0
  local s = tonumber(date("!%S", now)) or 0
  return (h * 3600) + (m * 60) + s
end

local function DailySecondsUntilReset(now)
  now = now or time()
  local nowSecs = GetUTCSecsOfDay(now)
  local resetSecs = (RESET_DAILY_H_UTC * 3600) + (RESET_DAILY_M_UTC * 60)

  if nowSecs < resetSecs then
    return resetSecs - nowSecs
  end
  return 86400 - (nowSecs - resetSecs)
end

local function WeeklySecondsUntilReset(now)
  now = now or time()
  local w = tonumber(date("!%w", now)) or 0
  local nowSecs = GetUTCSecsOfDay(now)
  local resetSecs = (RESET_WEEKLY_H_UTC * 3600) + (RESET_WEEKLY_M_UTC * 60)

  local daysSince = (w - RESET_WEEKLY_WDAY_UTC) % 7
  if daysSince == 0 and (nowSecs < resetSecs) then
    daysSince = 7
  end

  local secsSinceReset = (daysSince * 86400) + (nowSecs - resetSecs)
  local weekLen = 7 * 86400
  local remain = weekLen - secsSinceReset
  if remain < 0 then remain = 0 end
  return remain
end

local function FormatDuration(sec)
  sec = math.floor(tonumber(sec) or 0)
  if sec < 0 then sec = 0 end

  local days = math.floor(sec / 86400)
  local rem = sec % 86400
  local hh = math.floor(rem / 3600)
  rem = rem % 3600
  local mm = math.floor(rem / 60)
  local ss = rem % 60

  if days > 0 then
    return string.format("%dd %02d:%02d:%02d", days, hh, mm, ss)
  end
  return string.format("%02d:%02d:%02d", hh, mm, ss)
end

-- =========================================================
-- Priority / Sorting / Task helpers
-- =========================================================
-- 0 = none, 1 = P1 (highest), 2 = P2, 3 = P3 (lowest)
local function PriorityLabel(p)
  p = tonumber(p) or 0
  if p == 1 then return "P1" end
  if p == 2 then return "P2" end
  if p == 3 then return "P3" end
  return "P0"
end

local function PrioritySortKey(p)
  p = tonumber(p) or 0
  return (p == 0) and 99 or p
end

local function NormalizeCategory(cat)
  cat = tostring(cat or ""):gsub("^%s+", ""):gsub("%s+$", "")
  if cat == "" then cat = "General" end
  return cat
end

local function CategoryKey(cat)
  cat = NormalizeCategory(cat)
  if cat:lower() == "general" then return "" end
  return cat:lower()
end

local function SortListByCategoryPriority(list)
  if type(list) ~= "table" then return end
  table.sort(list, function(a, b)
    local ca = CategoryKey(a and a.category)
    local cb = CategoryKey(b and b.category)
    if ca ~= cb then return ca < cb end

    local pa = PrioritySortKey(a and a.priority)
    local pb = PrioritySortKey(b and b.priority)
    if pa ~= pb then return pa < pb end

    local ta = tostring(a and a.text or ""):lower()
    local tb = tostring(b and b.text or ""):lower()
    if ta ~= tb then return ta < tb end

    local xa = tonumber(a and a.created) or 0
    local xb = tonumber(b and b.created) or 0
    return xa < xb
  end)
end

local function NewTask(text, category)
  return {
    text = text,
    done = false,
    created = time(),
    note = "",
    priority = 0,
    category = NormalizeCategory(category),
  }
end

local function TaskHasNotes(task)
  if not task or not task.note then return false end
  return tostring(task.note):gsub("%s+", "") ~= ""
end

-- =========================================================
-- Sounds
-- =========================================================
local function PlayApplause()
  if PlaySound then
    pcall(function() PlaySound(12867, "SFX") end)
  end
end

-- =========================================================
-- Popups
-- =========================================================
local function PopupKey(suffix) return "FROSTEDSTASKLIST_" .. suffix end

local function EnsurePopup(name, text, onAccept)
  local key = PopupKey(name)
  if not StaticPopupDialogs[key] then
    StaticPopupDialogs[key] = {
      text = text,
      button1 = "Yes",
      button2 = "Cancel",
      OnAccept = onAccept,
      timeout = 0,
      whileDead = true,
      hideOnEscape = true,
      preferredIndex = 3,
    }
  else
    StaticPopupDialogs[key].text = text
    StaticPopupDialogs[key].OnAccept = onAccept
  end
  return key
end

-- =========================================================
-- Main Frame
-- =========================================================
local f = CreateFrame("Frame", "FrostedsTaskListFrame", UIParent, "BackdropTemplate")
f:SetSize(FrostedsTaskListDB.window.width, FrostedsTaskListDB.window.height)
f:SetPoint("CENTER")
f:SetMovable(true)
f:EnableMouse(true)
f:RegisterForDrag("LeftButton")
f:SetScript("OnDragStart", f.StartMoving)
f:SetScript("OnDragStop", f.StopMovingOrSizing)
f:SetResizable(true)
f:SetFrameStrata("DIALOG")
f:SetClampedToScreen(true)

f:SetBackdrop({
  bgFile = "Interface/Tooltips/UI-Tooltip-Background",
  edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
  tile = true, tileSize = 16, edgeSize = 16,
  insets = { left = 4, right = 4, top = 4, bottom = 4 }
})
f:SetBackdropColor(0, 0, 0, 0.88)

-- Hard minimum size
local MIN_W, MIN_H = 860, 470
local MAX_W, MAX_H = 1600, 1100

local _clamping = false
local function ClampSize()
  if _clamping then return end
  _clamping = true

  local w, h = f:GetSize()
  local nw = math.max(MIN_W, math.min(MAX_W, w))
  local nh = math.max(MIN_H, math.min(MAX_H, h))

  if nw ~= w or nh ~= h then
    f:SetSize(nw, nh)
  end

  FrostedsTaskListDB.window.width, FrostedsTaskListDB.window.height = f:GetSize()
  _clamping = false
end

f:HookScript("OnSizeChanged", ClampSize)

local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
title:SetPoint("TOPLEFT", 12, -10)
title:SetText("Frosted's Task List")

local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
close:SetPoint("TOPRIGHT", 2, 2)

local resetText = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
resetText:SetPoint("TOPRIGHT", f, "TOPRIGHT", -32, -14)
resetText:SetJustifyH("RIGHT")
resetText:SetText("")

local creditText = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
creditText:SetPoint("BOTTOM", f, "BOTTOM", 0, 6)
creditText:SetJustifyH("CENTER")
creditText:SetText("by Frosted - Goofdick of Enigma")

-- Resize handle (bottom-right)
local resizeButton = CreateFrame("Button", nil, f)
resizeButton:SetSize(18, 18)
resizeButton:SetPoint("BOTTOMRIGHT", -4, 4)
resizeButton:EnableMouse(true)

local rtUp = resizeButton:CreateTexture(nil, "ARTWORK")
rtUp:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
rtUp:SetAllPoints(resizeButton)
resizeButton:SetNormalTexture(rtUp)

local rtHL = resizeButton:CreateTexture(nil, "HIGHLIGHT")
rtHL:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
rtHL:SetAllPoints(resizeButton)
resizeButton:SetHighlightTexture(rtHL)

local rtDown = resizeButton:CreateTexture(nil, "OVERLAY")
rtDown:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
rtDown:SetAllPoints(resizeButton)
resizeButton:SetPushedTexture(rtDown)

-- Custom resize (no StartSizing -> no fighting clamp)
local resizing = false
local startCursorX, startCursorY, startW, startH

local function GetCursorScaled()
  local cx, cy = GetCursorPosition()
  local scale = UIParent:GetEffectiveScale() or 1
  return cx / scale, cy / scale
end

local function ApplyResizeFromCursor()
  if not resizing then return end

  local cx, cy = GetCursorScaled()
  local dx = cx - startCursorX
  local dy = startCursorY - cy

  local newW = startW + dx
  local newH = startH + dy

  newW = math.max(MIN_W, math.min(MAX_W, newW))
  newH = math.max(MIN_H, math.min(MAX_H, newH))

  f:SetSize(newW, newH)
  FrostedsTaskListDB.window.width = newW
  FrostedsTaskListDB.window.height = newH
end

resizeButton:SetScript("OnMouseDown", function()
  resizing = true
  startCursorX, startCursorY = GetCursorScaled()
  startW, startH = f:GetSize()
  f:SetScript("OnUpdate", ApplyResizeFromCursor)
end)

resizeButton:SetScript("OnMouseUp", function()
  resizing = false
  f:SetScript("OnUpdate", nil)
  ClampSize()
end)

-- Only open via /ftl
local function ShowMain()
  f:Show()
  f:Raise()
  FrostedsTaskListDB.shown = true
end

local function HideMain()
  f:Hide()
  FrostedsTaskListDB.shown = false
end

close:SetScript("OnClick", function() HideMain() end)

-- =========================================================
-- Layout
-- =========================================================
local PAD = 12
local NOTES_W = 260
local activeListKey = FrostedsTaskListDB.activeTab or "day"

local leftPane = CreateFrame("Frame", nil, f)
leftPane:SetPoint("TOPLEFT", PAD, -36)
leftPane:SetPoint("BOTTOMRIGHT", -(NOTES_W + PAD + 10), 40)

local notesPanel = CreateFrame("Frame", nil, f, "BackdropTemplate")
notesPanel:SetPoint("TOPRIGHT", -PAD, -36)
notesPanel:SetPoint("BOTTOMRIGHT", -PAD, 40)
notesPanel:SetWidth(NOTES_W)
notesPanel:SetBackdrop({
  bgFile = "Interface/Tooltips/UI-Tooltip-Background",
  edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
  tile = true, tileSize = 16, edgeSize = 12,
  insets = { left = 4, right = 4, top = 4, bottom = 4 }
})
notesPanel:SetBackdropColor(0, 0, 0, 0.55)

-- Tabs
local dailyTab = CreateFrame("Button", nil, leftPane, "UIPanelButtonTemplate")
dailyTab:SetSize(80, 22)
dailyTab:SetPoint("TOPLEFT", 0, 0)
dailyTab:SetText("Daily")

local weeklyTab = CreateFrame("Button", nil, leftPane, "UIPanelButtonTemplate")
weeklyTab:SetSize(80, 22)
weeklyTab:SetPoint("LEFT", dailyTab, "RIGHT", 6, 0)
weeklyTab:SetText("Weekly")

local instTab = CreateFrame("Button", nil, leftPane, "UIPanelButtonTemplate")
instTab:SetSize(90, 22)
instTab:SetPoint("LEFT", weeklyTab, "RIGHT", 6, 0)
instTab:SetText("Instances")

local miscTab = CreateFrame("Button", nil, leftPane, "UIPanelButtonTemplate")
miscTab:SetSize(80, 22)
miscTab:SetPoint("LEFT", instTab, "RIGHT", 6, 0)
miscTab:SetText("Misc")

-- =========================================================
-- Filters
-- =========================================================
local function GetFilterState()
  FrostedsTaskListDB.filters[activeListKey] = FrostedsTaskListDB.filters[activeListKey] or {
    search = "", hideDone = false, hasNotes = false, pri = { [0]=true, [1]=true, [2]=true, [3]=true }
  }
  return FrostedsTaskListDB.filters[activeListKey]
end

local filterLabel = leftPane:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
filterLabel:SetPoint("TOPLEFT", 0, -26)
filterLabel:SetText("Search / Filters")

local searchBox = CreateFrame("EditBox", nil, leftPane, "InputBoxTemplate")
searchBox:SetSize(190, 22)
searchBox:SetPoint("TOPLEFT", 0, -44)
searchBox:SetAutoFocus(false)
searchBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

local hideDoneBtn = CreateFrame("Button", nil, leftPane, "UIPanelButtonTemplate")
hideDoneBtn:SetSize(95, 22)
hideDoneBtn:SetPoint("LEFT", searchBox, "RIGHT", 8, 0)

local hasNotesBtn = CreateFrame("Button", nil, leftPane, "UIPanelButtonTemplate")
hasNotesBtn:SetSize(95, 22)
hasNotesBtn:SetPoint("LEFT", hideDoneBtn, "RIGHT", 6, 0)

local priBtn0 = CreateFrame("Button", nil, leftPane, "UIPanelButtonTemplate")
priBtn0:SetSize(36, 22)
priBtn0:SetPoint("LEFT", hasNotesBtn, "RIGHT", 10, 0)

local priBtn1 = CreateFrame("Button", nil, leftPane, "UIPanelButtonTemplate")
priBtn1:SetSize(36, 22)
priBtn1:SetPoint("LEFT", priBtn0, "RIGHT", 4, 0)

local priBtn2 = CreateFrame("Button", nil, leftPane, "UIPanelButtonTemplate")
priBtn2:SetSize(36, 22)
priBtn2:SetPoint("LEFT", priBtn1, "RIGHT", 4, 0)

local priBtn3 = CreateFrame("Button", nil, leftPane, "UIPanelButtonTemplate")
priBtn3:SetSize(36, 22)
priBtn3:SetPoint("LEFT", priBtn2, "RIGHT", 4, 0)

local function AnyPrioritySelected(priTbl)
  if type(priTbl) ~= "table" then return false end
  return (priTbl[0] or priTbl[1] or priTbl[2] or priTbl[3]) and true or false
end

local function TaskMatchesFilters(task, fs)
  if not task then return false end
  fs = fs or GetFilterState()

  if fs.hideDone and task.done then return false end
  if fs.hasNotes and not TaskHasNotes(task) then return false end

  local priTbl = fs.pri or {}
  if AnyPrioritySelected(priTbl) then
    local p = tonumber(task.priority) or 0
    if not priTbl[p] then return false end
  end

  local s = tostring(fs.search or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
  if s ~= "" then
    local text = tostring(task.text or ""):lower()
    local note = tostring(task.note or ""):lower()
    if (not string.find(text, s, 1, true)) and (not string.find(note, s, 1, true)) then
      return false
    end
  end

  return true
end

local refreshPending = false
local function RequestRefresh(fn)
  if refreshPending then return end
  refreshPending = true
  C_Timer.After(0.15, function()
    refreshPending = false
    if fn then fn() end
  end)
end

local function UpdateFilterButtons()
  local fs = GetFilterState()
  searchBox:SetText(fs.search or "")
  hideDoneBtn:SetText((fs.hideDone and "[x] Hide Done") or "[ ] Hide Done")
  hasNotesBtn:SetText((fs.hasNotes and "[x] Has Notes") or "[ ] Has Notes")

  local pri = fs.pri or {}
  priBtn0:SetText((pri[0] and "[P0]") or " P0 ")
  priBtn1:SetText((pri[1] and "[P1]") or " P1 ")
  priBtn2:SetText((pri[2] and "[P2]") or " P2 ")
  priBtn3:SetText((pri[3] and "[P3]") or " P3 ")
end

-- =========================================================
-- Add Task Row
-- =========================================================
local addLabel = leftPane:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
addLabel:SetPoint("TOPLEFT", 0, -70)
addLabel:SetText("Add Task")

local input = CreateFrame("EditBox", nil, leftPane, "InputBoxTemplate")
input:SetSize(260, 24)
input:SetPoint("TOPLEFT", 0, -88)
input:SetAutoFocus(false)
input:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

local catBox = CreateFrame("EditBox", nil, leftPane, "InputBoxTemplate")
catBox:SetSize(120, 24)
catBox:SetPoint("LEFT", input, "RIGHT", 8, 0)
catBox:SetAutoFocus(false)
catBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

local addBtn = CreateFrame("Button", nil, leftPane, "UIPanelButtonTemplate")
addBtn:SetSize(85, 24)
addBtn:SetPoint("LEFT", catBox, "RIGHT", 8, 0)
addBtn:SetText("Add")

-- =========================================================
-- Scroll List
-- =========================================================
local scroll = CreateFrame("ScrollFrame", nil, leftPane, "UIPanelScrollFrameTemplate")
scroll:SetPoint("TOPLEFT", 0, -120)
scroll:SetPoint("BOTTOMRIGHT", -24, 36)

local content = CreateFrame("Frame", nil, scroll)
content:SetSize(1, 1)
scroll:SetScrollChild(content)

scroll:HookScript("OnSizeChanged", function()
  local w = scroll:GetWidth() or 1
  content:SetWidth(math.max(1, w - 18))
end)

-- =========================================================
-- Notes Panel
-- =========================================================
local notesTitle = notesPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
notesTitle:SetPoint("TOPLEFT", 10, -10)
notesTitle:SetText("Notes")

local notesTaskLabel = notesPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
notesTaskLabel:SetPoint("TOPLEFT", 10, -30)
notesTaskLabel:SetPoint("TOPRIGHT", -10, -30)
notesTaskLabel:SetJustifyH("LEFT")
notesTaskLabel:SetText("Select a task.")

local catLabel2 = notesPanel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
catLabel2:SetPoint("TOPLEFT", 10, -50)
catLabel2:SetText("Category")

local notesCatBox = CreateFrame("EditBox", nil, notesPanel, "InputBoxTemplate")
notesCatBox:SetSize(150, 20)
notesCatBox:SetPoint("TOPLEFT", 10, -64)
notesCatBox:SetAutoFocus(false)
notesCatBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

local priLabel2 = notesPanel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
priLabel2:SetPoint("LEFT", notesCatBox, "RIGHT", 8, 0)
priLabel2:SetText("Pri")

local npP0 = CreateFrame("Button", nil, notesPanel, "UIPanelButtonTemplate")
npP0:SetSize(28, 20)
npP0:SetPoint("LEFT", priLabel2, "RIGHT", 6, 0)
npP0:SetText("0")

local npP1 = CreateFrame("Button", nil, notesPanel, "UIPanelButtonTemplate")
npP1:SetSize(28, 20)
npP1:SetPoint("LEFT", npP0, "RIGHT", 4, 0)
npP1:SetText("1")

local npP2 = CreateFrame("Button", nil, notesPanel, "UIPanelButtonTemplate")
npP2:SetSize(28, 20)
npP2:SetPoint("LEFT", npP1, "RIGHT", 4, 0)
npP2:SetText("2")

local npP3 = CreateFrame("Button", nil, notesPanel, "UIPanelButtonTemplate")
npP3:SetSize(28, 20)
npP3:SetPoint("LEFT", npP2, "RIGHT", 4, 0)
npP3:SetText("3")

local notesScroll = CreateFrame("ScrollFrame", nil, notesPanel, "UIPanelScrollFrameTemplate")
notesScroll:SetPoint("TOPLEFT", 10, -92)
notesScroll:SetPoint("BOTTOMRIGHT", -28, 44)

local notesEdit = CreateFrame("EditBox", nil, notesScroll)
notesEdit:SetMultiLine(true)
notesEdit:SetAutoFocus(false)
notesEdit:EnableMouse(true)
notesEdit:SetFontObject(ChatFontNormal)
notesEdit:SetTextInsets(6, 6, 6, 6)
notesEdit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
notesEdit:SetScript("OnTextChanged", function(self)
  notesScroll:UpdateScrollChildRect()
end)
notesScroll:SetScrollChild(notesEdit)

notesScroll:HookScript("OnSizeChanged", function()
  local w = notesScroll:GetWidth() or 1
  notesEdit:SetWidth(math.max(1, w))
end)

local clearNoteBtn = CreateFrame("Button", nil, notesPanel, "UIPanelButtonTemplate")
clearNoteBtn:SetSize(90, 20)
clearNoteBtn:SetPoint("BOTTOMRIGHT", -10, 12)
clearNoteBtn:SetText("Clear Note")

local saveNoteBtn = CreateFrame("Button", nil, notesPanel, "UIPanelButtonTemplate")
saveNoteBtn:SetSize(60, 20)
saveNoteBtn:SetPoint("RIGHT", clearNoteBtn, "LEFT", -6, 0)
saveNoteBtn:SetText("Save")

local function SetNotesEnabled(enabled)
  notesCatBox:SetEnabled(enabled)
  notesEdit:SetEnabled(enabled)
  saveNoteBtn:SetEnabled(enabled)
  clearNoteBtn:SetEnabled(enabled)

  local a = enabled and 1.0 or 0.5
  notesCatBox:SetAlpha(a)
  notesEdit:SetAlpha(a)
  saveNoteBtn:SetAlpha(a)
  clearNoteBtn:SetAlpha(a)
end

-- =========================================================
-- Active list + selection
-- =========================================================
local selectedTask = nil
local selectedTaskListKey = nil

local function GetActiveList()
  FrostedsTaskListDB[activeListKey] = FrostedsTaskListDB[activeListKey] or {}
  return FrostedsTaskListDB[activeListKey]
end

local function GetCollapsedMap()
  FrostedsTaskListDB.collapsedCategories[activeListKey] = FrostedsTaskListDB.collapsedCategories[activeListKey] or {}
  return FrostedsTaskListDB.collapsedCategories[activeListKey]
end

local function FindTaskIndex(list, taskRef)
  if type(list) ~= "table" or not taskRef then return nil end
  for i = 1, #list do
    if list[i] == taskRef then return i end
  end
  return nil
end

local function SelectTask(taskRef)
  selectedTask = taskRef
  selectedTaskListKey = activeListKey

  if not selectedTask then
    notesTaskLabel:SetText("Select a task.")
    notesCatBox:SetText("")
    notesEdit:SetText("")
    SetNotesEnabled(false)
    return
  end

  SetNotesEnabled(true)
  notesTaskLabel:SetText("Task: " .. tostring(selectedTask.text or ""))
  notesCatBox:SetText(NormalizeCategory(selectedTask.category))
  notesEdit:SetText(selectedTask.note or "")
end

SetNotesEnabled(false)

-- =========================================================
-- Filter wiring
-- =========================================================
hideDoneBtn:SetScript("OnClick", function()
  local fs = GetFilterState()
  fs.hideDone = not fs.hideDone
  UpdateFilterButtons()
  if f:IsShown() then Refresh() end
end)

hasNotesBtn:SetScript("OnClick", function()
  local fs = GetFilterState()
  fs.hasNotes = not fs.hasNotes
  UpdateFilterButtons()
  if f:IsShown() then Refresh() end
end)

local function TogglePri(p)
  local fs = GetFilterState()
  fs.pri = fs.pri or { [0]=true, [1]=true, [2]=true, [3]=true }
  fs.pri[p] = not fs.pri[p]
  UpdateFilterButtons()
  if f:IsShown() then Refresh() end
end

priBtn0:SetScript("OnClick", function() TogglePri(0) end)
priBtn1:SetScript("OnClick", function() TogglePri(1) end)
priBtn2:SetScript("OnClick", function() TogglePri(2) end)
priBtn3:SetScript("OnClick", function() TogglePri(3) end)

searchBox:SetScript("OnTextChanged", function(self)
  local fs = GetFilterState()
  fs.search = self:GetText() or ""
  RequestRefresh(function()
    if f:IsShown() then Refresh() end
  end)
end)

-- =========================================================
-- Add Task
-- =========================================================
local function AddFromInput()
  local t = (input:GetText() or ""):gsub("^%s+", ""):gsub("%s+$", "")
  if t == "" then return end

  local c = (catBox:GetText() or ""):gsub("^%s+", ""):gsub("%s+$", "")

  local list = GetActiveList()
  table.insert(list, NewTask(t, c))
  SortListByCategoryPriority(list)

  input:SetText("")
  input:ClearFocus()

  if f:IsShown() then Refresh() end
end

addBtn:SetScript("OnClick", AddFromInput)
input:SetScript("OnEnterPressed", AddFromInput)
catBox:SetScript("OnEnterPressed", AddFromInput)

-- =========================================================
-- Notes panel behavior
-- =========================================================
saveNoteBtn:SetScript("OnClick", function()
  if not selectedTask then return end
  selectedTask.note = notesEdit:GetText() or ""
  selectedTask.category = NormalizeCategory(notesCatBox:GetText() or selectedTask.category)
  SortListByCategoryPriority(GetActiveList())
  if f:IsShown() then Refresh() end
end)

clearNoteBtn:SetScript("OnClick", function()
  if not selectedTask then return end
  StaticPopup_Show(EnsurePopup(
    "CONFIRM_CLEAR_NOTE",
    "Clear this note? (This will remove all text for this task.)",
    function()
      if not selectedTask then return end
      notesEdit:SetText("")
      selectedTask.note = ""
      if f:IsShown() then Refresh() end
    end
  ))
end)

notesEdit:SetScript("OnTextChanged", function(self)
  notesScroll:UpdateScrollChildRect()
  if not selectedTask then return end
  selectedTask.note = self:GetText() or ""
  RequestRefresh(function()
    if f:IsShown() then Refresh() end
  end)
end)

notesCatBox:SetScript("OnEnterPressed", function(self)
  self:ClearFocus()
  if not selectedTask then return end
  selectedTask.category = NormalizeCategory(self:GetText())
  SortListByCategoryPriority(GetActiveList())
  if f:IsShown() then Refresh() end
end)

notesCatBox:SetScript("OnEditFocusLost", function(self)
  if not selectedTask then return end
  selectedTask.category = NormalizeCategory(self:GetText())
  SortListByCategoryPriority(GetActiveList())
  if f:IsShown() then Refresh() end
end)

local function SetSelectedPriority(p)
  if not selectedTask then return end
  selectedTask.priority = tonumber(p) or 0
  SortListByCategoryPriority(GetActiveList())
  if f:IsShown() then Refresh() end
end

npP0:SetScript("OnClick", function() SetSelectedPriority(0) end)
npP1:SetScript("OnClick", function() SetSelectedPriority(1) end)
npP2:SetScript("OnClick", function() SetSelectedPriority(2) end)
npP3:SetScript("OnClick", function() SetSelectedPriority(3) end)

-- =========================================================
-- Bottom buttons
-- =========================================================
local clearChecksBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
clearChecksBtn:SetSize(140, 24)
clearChecksBtn:SetPoint("BOTTOMLEFT", PAD, 12)
clearChecksBtn:SetText("Clear checks")

local clearTabBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
clearTabBtn:SetSize(120, 24)
clearTabBtn:SetPoint("LEFT", clearChecksBtn, "RIGHT", 10, 0)
clearTabBtn:SetText("Clear tab")

local sortBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
sortBtn:SetSize(70, 24)
sortBtn:SetPoint("LEFT", clearTabBtn, "RIGHT", 10, 0)
sortBtn:SetText("Sort")

clearChecksBtn:SetScript("OnClick", function()
  local list = GetActiveList()
  if #list == 0 then return end
  StaticPopup_Show(EnsurePopup(
    "CONFIRM_CLEAR_CHECKS",
    "Clear all checkmarks in this tab?",
    function()
      ClearCompletion(list)
      if f:IsShown() then Refresh() end
    end
  ))
end)

clearTabBtn:SetScript("OnClick", function()
  local list = GetActiveList()
  if #list == 0 then return end
  StaticPopup_Show(EnsurePopup(
    "CONFIRM_CLEAR_TAB",
    "Clear ALL tasks in this tab?",
    function()
      FrostedsTaskListDB[activeListKey] = {}
      SelectTask(nil)
      if f:IsShown() then Refresh() end
    end
  ))
end)

sortBtn:SetScript("OnClick", function()
  local list = GetActiveList()
  SortListByCategoryPriority(list)
  if f:IsShown() then Refresh() end
end)

-- =========================================================
-- /ftl toggle (ONLY way to open)
-- =========================================================
local function ToggleMain()
  if f:IsShown() then
    HideMain()
  else
    ShowMain()
    Refresh()
  end
end

SLASH_FROSTEDSTTASKLIST1 = "/ftl"
SlashCmdList["FROSTEDSTTASKLIST"] = function()
  ToggleMain()
end

_G.FrostedsTaskList_Toggle = function()
  ToggleMain()
end

-- =========================================================
-- Init / Tickers
-- =========================================================
local resetTicker
local countdownTicker

local evt = CreateFrame("Frame")
evt:RegisterEvent("PLAYER_LOGIN")
evt:RegisterEvent("PLAYER_ENTERING_WORLD")

evt:SetScript("OnEvent", function(_, event)
  if event == "PLAYER_LOGIN" then
    ApplyDefaults()
    MaybeResetLists()

    ClampSize()
    HideMain()

    UpdateFilterButtons()
    SelectTask(nil)

    if not resetTicker and C_Timer and C_Timer.NewTicker then
      resetTicker = C_Timer.NewTicker(60, function()
        local reset = MaybeResetLists()
        if reset and f:IsShown() then
          Refresh()
        end
      end)
    end

    if not countdownTicker and C_Timer and C_Timer.NewTicker then
      countdownTicker = C_Timer.NewTicker(1, function()
        if f:IsShown() then
          if activeListKey == "day" then
            resetText:SetText("Reset in " .. FormatDuration(DailySecondsUntilReset()))
          elseif activeListKey == "week" then
            resetText:SetText("Reset in " .. FormatDuration(WeeklySecondsUntilReset()))
          else
            resetText:SetText("")
          end
        end
      end)
    end
  elseif event == "PLAYER_ENTERING_WORLD" then
    local reset = MaybeResetLists()
    if reset and f:IsShown() then
      Refresh()
    end
  end
end)

-- =========================================================
-- Tab click handlers
-- =========================================================
local function SwitchTab(key)
  activeListKey = key
  FrostedsTaskListDB.activeTab = key
  SelectTask(nil)
  UpdateFilterButtons()
  Refresh()
end

dailyTab:SetScript("OnClick",  function() SwitchTab("day")       end)
weeklyTab:SetScript("OnClick", function() SwitchTab("week")      end)
instTab:SetScript("OnClick",   function() SwitchTab("instances") end)
miscTab:SetScript("OnClick",   function() SwitchTab("misc")      end)

-- =========================================================
-- Row pool (reuse frames instead of creating/destroying)
-- =========================================================
local rowPool    = {}
local activeRows = {}
local ROW_H = 22
local CAT_H = 20

local function AcquireRow()
  local r = table.remove(rowPool)
  if not r then
    r = CreateFrame("Frame", nil, content)
  end
  r:SetParent(content)
  r:Show()
  table.insert(activeRows, r)
  return r
end

local function ReleaseAllRows()
  for _, r in ipairs(activeRows) do
    r:Hide()
    r:ClearAllPoints()
    r:EnableMouse(false)
    r:SetScript("OnMouseDown", nil)
    r:SetScript("OnEnter",     nil)
    r:SetScript("OnLeave",     nil)
    table.insert(rowPool, r)
  end
  wipe(activeRows)
end

-- =========================================================
-- Refresh (render the task list)
-- =========================================================
function Refresh()
  ReleaseAllRows()

  local list      = GetActiveList()
  SortListByCategoryPriority(list)
  local fs        = GetFilterState()
  local collapsed = GetCollapsedMap()
  local cW        = content:GetWidth()
  if cW < 100 then cW = math.max(100, (scroll:GetWidth() or 100) - 18) end
  local yOff      = 0

  -- Build ordered category list
  local catOrder = {}
  local catData  = {}
  local catSeen  = {}
  for i = 1, #list do
    local task = list[i]
    local ck   = CategoryKey(task.category)
    if not catSeen[ck] then
      catSeen[ck] = true
      table.insert(catOrder, ck)
      catData[ck] = { name = NormalizeCategory(task.category), all = {} }
    end
    table.insert(catData[ck].all, task)
  end

  local anyVisible = false

  for _, ck in ipairs(catOrder) do
    local info     = catData[ck]
    local allTasks = info.all

    local visible = {}
    for _, t in ipairs(allTasks) do
      if TaskMatchesFilters(t, fs) then
        table.insert(visible, t)
      end
    end

    if #visible > 0 then
      anyVisible = true

      local doneCount = 0
      for _, t in ipairs(allTasks) do if t.done then doneCount = doneCount + 1 end end

      -- ---- Category header ----
      local hRow = AcquireRow()
      hRow:SetSize(cW, CAT_H)
      hRow:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -yOff)
      hRow:EnableMouse(true)

      if not hRow._catBg then
        hRow._catBg = hRow:CreateTexture(nil, "BACKGROUND")
        hRow._catBg:SetAllPoints()
      end
      hRow._catBg:SetColorTexture(0.12, 0.12, 0.22, 0.9)
      hRow._catBg:Show()

      if not hRow._arrow then
        hRow._arrow = hRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        hRow._arrow:SetSize(14, CAT_H)
        hRow._arrow:SetPoint("LEFT", 2, 0)
        hRow._arrow:SetJustifyH("CENTER")
      end
      hRow._arrow:SetText(collapsed[ck] and "+" or "-")
      hRow._arrow:Show()

      if not hRow._catLabel then
        hRow._catLabel = hRow:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        hRow._catLabel:SetPoint("LEFT", 18, 0)
        hRow._catLabel:SetPoint("RIGHT", -4, 0)
        hRow._catLabel:SetJustifyH("LEFT")
      end
      hRow._catLabel:SetText(info.name .. "  |cFFAAAAAA(" .. doneCount .. "/" .. #allTasks .. ")|r")
      hRow._catLabel:Show()

      -- Hide task-type elements if frame was previously a task row
      if hRow._selBg   then hRow._selBg:Hide()   end
      if hRow._check   then hRow._check:Hide()    end
      if hRow._priLbl  then hRow._priLbl:Hide()   end
      if hRow._txtLbl  then hRow._txtLbl:Hide()   end
      if hRow._noteIco then hRow._noteIco:Hide()  end
      if hRow._delBtn  then hRow._delBtn:Hide()   end

      local capturedCk = ck
      hRow:SetScript("OnMouseDown", function()
        collapsed[capturedCk] = not collapsed[capturedCk]
        Refresh()
      end)

      yOff = yOff + CAT_H + 2

      -- ---- Task rows (if category not collapsed) ----
      if not collapsed[ck] then
        for _, task in ipairs(visible) do
          local tRow = AcquireRow()
          tRow:SetSize(cW, ROW_H)
          tRow:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -yOff)
          tRow:EnableMouse(true)

          -- Hide header-type elements if frame was previously a header row
          if tRow._catBg    then tRow._catBg:Hide()    end
          if tRow._arrow    then tRow._arrow:Hide()    end
          if tRow._catLabel then tRow._catLabel:Hide() end

          -- Selection highlight
          if not tRow._selBg then
            tRow._selBg = tRow:CreateTexture(nil, "BACKGROUND")
            tRow._selBg:SetAllPoints()
            tRow._selBg:SetColorTexture(0.3, 0.5, 0.9, 0.25)
          end
          tRow._selBg:SetShown(selectedTask == task)

          tRow:SetScript("OnEnter", function(self)
            if selectedTask ~= task then
              self._selBg:SetColorTexture(0.3, 0.5, 0.9, 0.12)
              self._selBg:Show()
            end
          end)
          tRow:SetScript("OnLeave", function(self)
            self._selBg:SetColorTexture(0.3, 0.5, 0.9, 0.25)
            self._selBg:SetShown(selectedTask == task)
          end)

          local capturedTask = task
          tRow:SetScript("OnMouseDown", function()
            SelectTask(capturedTask)
            Refresh()
          end)

          -- Checkbox
          if not tRow._check then
            tRow._check = CreateFrame("CheckButton", nil, tRow, "UICheckButtonTemplate")
            tRow._check:SetSize(20, 20)
            tRow._check:SetPoint("LEFT", 2, 0)
          end
          tRow._check:Show()
          tRow._check:SetChecked(task.done)
          tRow._check:SetScript("OnClick", function(self)
            task.done = self:GetChecked()
            if task.done then PlayApplause() end
            Refresh()
          end)

          -- Priority label
          if not tRow._priLbl then
            tRow._priLbl = tRow:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            tRow._priLbl:SetSize(26, ROW_H)
            tRow._priLbl:SetPoint("LEFT", 24, 0)
            tRow._priLbl:SetJustifyH("LEFT")
          end
          tRow._priLbl:Show()
          local p = tonumber(task.priority) or 0
          if     p == 1 then tRow._priLbl:SetText("|cFFFF4444P1|r")
          elseif p == 2 then tRow._priLbl:SetText("|cFFFFAA00P2|r")
          elseif p == 3 then tRow._priLbl:SetText("|cFFFFFF44P3|r")
          else               tRow._priLbl:SetText("") end

          -- Task text
          if not tRow._txtLbl then
            tRow._txtLbl = tRow:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            tRow._txtLbl:SetPoint("LEFT", 52, 0)
            tRow._txtLbl:SetPoint("RIGHT", -54, 0)
            tRow._txtLbl:SetJustifyH("LEFT")
            tRow._txtLbl:SetWordWrap(false)
          end
          tRow._txtLbl:Show()
          tRow._txtLbl:SetText(task.done
            and ("|cFF888888" .. tostring(task.text or "") .. "|r")
            or  tostring(task.text or ""))

          -- Has-notes indicator
          if not tRow._noteIco then
            tRow._noteIco = tRow:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            tRow._noteIco:SetSize(14, ROW_H)
            tRow._noteIco:SetPoint("RIGHT", -32, 0)
            tRow._noteIco:SetJustifyH("CENTER")
          end
          tRow._noteIco:Show()
          tRow._noteIco:SetText(TaskHasNotes(task) and "|cFF88FFFF*|r" or "")

          -- Delete button
          if not tRow._delBtn then
            tRow._delBtn = CreateFrame("Button", nil, tRow, "UIPanelButtonTemplate")
            tRow._delBtn:SetSize(28, 18)
            tRow._delBtn:SetPoint("RIGHT", -2, 0)
            tRow._delBtn:SetText("X")
          end
          tRow._delBtn:Show()
          tRow._delBtn:SetScript("OnClick", function()
            local taskList = FrostedsTaskListDB[activeListKey]
            local idx = FindTaskIndex(taskList, capturedTask)
            if idx then table.remove(taskList, idx) end
            if selectedTask == capturedTask then SelectTask(nil) end
            Refresh()
          end)

          yOff = yOff + ROW_H + 2
        end
      end
    end
  end

  -- Empty state
  if not anyVisible then
    local eRow = AcquireRow()
    eRow:SetSize(cW, 24)
    eRow:SetPoint("TOPLEFT", content, "TOPLEFT", 4, 0)
    eRow:EnableMouse(false)
    if eRow._catBg    then eRow._catBg:Hide()    end
    if eRow._arrow    then eRow._arrow:Hide()    end
    if eRow._selBg    then eRow._selBg:Hide()    end
    if eRow._check    then eRow._check:Hide()    end
    if eRow._priLbl   then eRow._priLbl:Hide()   end
    if eRow._noteIco  then eRow._noteIco:Hide()  end
    if eRow._delBtn   then eRow._delBtn:Hide()   end
    if not eRow._catLabel then
      eRow._catLabel = eRow:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
      eRow._catLabel:SetAllPoints()
      eRow._catLabel:SetJustifyH("LEFT")
    end
    eRow._catLabel:SetText("No tasks. Use the field above to add one.")
    eRow._catLabel:Show()
    yOff = 26
  end

  content:SetHeight(math.max(1, yOff))

  -- Update reset timer label
  if activeListKey == "day" then
    resetText:SetText("Reset in " .. FormatDuration(DailySecondsUntilReset()))
  elseif activeListKey == "week" then
    resetText:SetText("Reset in " .. FormatDuration(WeeklySecondsUntilReset()))
  else
    resetText:SetText("")
  end
end

-- start hidden
f:Hide()
ClampSize()
UpdateFilterButtons()
SelectTask(nil)