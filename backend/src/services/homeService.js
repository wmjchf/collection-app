const systemFilterService = require('./systemFilterService');
const { mapItem } = require('./itemService');

async function section(userId, code, tzOffsetMinutes) {
  const result = await systemFilterService.listItemsBySystemFilter(userId, code, {
    tzOffsetMinutes,
    limit: 3,
    offset: 0,
  });
  const items = result.items.map(mapItem);

  return {
    total: result.total,
    items,
  };
}

/** 首页两板块：未读 / 最近阅读（各最多 3 条） */
async function getHome(userId, tzOffsetMinutes = 480) {
  const [unread, recentRead] = await Promise.all([
    section(userId, 'unread', tzOffsetMinutes),
    section(userId, 'recent_read', tzOffsetMinutes),
  ]);

  return { unread, recentRead };
}

module.exports = { getHome };
