// src/services/complaintService.js
// ─────────────────────────────────────────────────────────────
// Complaint Service (Business Logic Layer)
// ─────────────────────────────────────────────────────────────

const Complaint = require('../models/Complaint');
const Upvote = require('../models/Upvote');
const User = require('../models/User');
const { createNotification } = require('./notificationService');
const { detectAndUpdateUrgency } = require('./urgencyService');
const { scopeFilterForUser, serializeComplaint } = require('./complaintAccess');

/**
 * Creates a new complaint.
 */
const createComplaint = async (dbUser, firebaseUid, data) => {
  const { category, description, lat, lng, imageUrl, voiceNoteUrl } = data;

  const location = {
    type: 'Point',
    coordinates: [lng, lat],
  };

  const complaint = new Complaint({
    userId: dbUser._id,
    firebaseUid,
    category,
    description: description || '',
    location,
    imageUrl: imageUrl || null,
    voiceNoteUrl: voiceNoteUrl || null,
    urgencyClassification: 'pending',
  });

  // Initialize status history
  complaint.statusHistory.push({
    status: 'Pending',
    changedBy: dbUser._id,
    note: 'Complaint submitted by citizen.',
  });

  const savedComplaint = await complaint.save();

  // Trigger AI urgency detection asynchronously (fire-and-forget).
  // Pass voiceNoteUrl so the service can also transcribe the audio
  // and use the combined text for a more accurate urgency classification.
  detectAndUpdateUrgency(savedComplaint._id.toString(), description, voiceNoteUrl || null);

  User.find({ role: 'department_staff', department: category }).then(staffToNotify => {
    staffToNotify.forEach(staff => {
      createNotification({
        userId: staff._id,
        complaintId: savedComplaint._id,
        type: 'new_complaint',
        message: `New ${category} complaint filed in your department.`,
      });
    });
  }).catch(console.error);

  return serializeComplaint(savedComplaint, dbUser, false);
};

/**
 * Lists complaints with pagination and filtering.
 */
const listComplaints = async (dbUser, query) => {
  const {
    category, status, urgency,
    page = 1, limit = 20,
    sortBy = 'createdAt',
    order = 'desc',   // 'asc' | 'desc'
    days,             // restrict to last N days
    search,           // text search in description
  } = query;

  const safeLimit = Math.min(parseInt(limit, 10) || 20, 100);
  const safePage = Math.max(parseInt(page, 10) || 1, 1);

  const ALLOWED_SORT_FIELDS = ['createdAt', 'upvotes', 'urgency', 'updatedAt'];
  const sortField = ALLOWED_SORT_FIELDS.includes(sortBy) ? sortBy : 'createdAt';
  const sortDir   = order === 'asc' ? 1 : -1;

  let filter = {};
  if (category) filter.category = category;

  if (status) {
    const VALID_STATUSES = ['Pending', 'In Progress', 'Resolved', 'Rejected'];
    const statuses = status.split(',').map(s => s.trim()).filter(s => VALID_STATUSES.includes(s));
    if (statuses.length > 0) {
      filter.status = statuses.length === 1 ? statuses[0] : { $in: statuses };
    }
  }

  if (urgency) filter.urgency = urgency;

  // Date range filter
  if (days && days !== 'all') {
    const since = new Date();
    since.setDate(since.getDate() - parseInt(days, 10));
    filter.createdAt = { $gte: since };
  }

  // Text search in description (case-insensitive regex)
  if (search && search.trim()) {
    const escapeRegex = (str) => str.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
    filter.description = { $regex: escapeRegex(search.trim()), $options: 'i' };
  }

  filter = scopeFilterForUser(dbUser, filter);

  const skip  = (safePage - 1) * safeLimit;
  const total = await Complaint.countDocuments(filter);

  const complaints = await Complaint.find(filter)
    .sort({ [sortField]: sortDir })
    .skip(skip)
    .limit(safeLimit)
    .populate('userId', 'name email phone')
    .lean();

  const userUpvotes = await Upvote.find({
    userId: dbUser._id,
    complaintId: { $in: complaints.map(c => c._id) }
  }).lean();
  const upvotedSet = new Set(userUpvotes.map(u => String(u.complaintId)));

  return {
    data: complaints.map((c) => serializeComplaint(c, dbUser, upvotedSet.has(String(c._id)))),
    pagination: {
      total,
      page:       safePage,
      limit:      safeLimit,
      totalPages: Math.ceil(total / safeLimit),
    },
  };
};

/**
 * Lists complaints filed by the current user.
 */
const listMyComplaints = async (dbUser) => {
  const complaints = await Complaint.find({ userId: dbUser._id })
    .sort({ createdAt: -1 })
    .lean();

  const userUpvotes = await Upvote.find({
    userId: dbUser._id,
    complaintId: { $in: complaints.map(c => c._id) }
  }).lean();
  const upvotedSet = new Set(userUpvotes.map(u => String(u.complaintId)));

  return complaints.map((c) => serializeComplaint(c, dbUser, upvotedSet.has(String(c._id))));
};

/**
 * Retrieves a single complaint by ID.
 */
const getComplaintById = async (dbUser, id) => {
  const complaint = await Complaint.findOne(scopeFilterForUser(dbUser, { _id: id }))
    .populate('userId', 'name email phone')
    .populate({
      path: 'statusHistory.changedBy',
      select: 'name role department',
    });

  if (!complaint) return null;
  const userUpvote = await Upvote.findOne({ userId: dbUser._id, complaintId: complaint._id });
  return serializeComplaint(complaint, dbUser, !!userUpvote);
};

/**
 * Updates status of a complaint.
 */
const updateComplaintStatus = async (dbUser, id, status, note = '') => {
  const complaint = await Complaint.findById(id);
  if (!complaint) return { error: 404, message: 'Complaint not found' };

  // Access Control: department staff only update own category
  if (dbUser.role === 'department_staff' && dbUser.department !== complaint.category) {
    return { error: 403, message: 'You can only update complaints in your own department.' };
  }

  const previousStatus = complaint.status;
  if (previousStatus !== status) {
    complaint.status = status;
    complaint.statusHistory.push({
      status,
      changedBy: dbUser._id,
      note: note || `Status updated to ${status} by department staff.`,
    });
    await complaint.save();

    // Trigger Notification
    if (complaint.userId) {
      createNotification({
        userId: complaint.userId,
        complaintId: complaint._id,
        type: 'status_update',
        message: `Your complaint "${complaint.category}" status has been updated to "${status}".`,
      });
    }
  }

  return { data: { id: complaint._id, status: complaint.status } };
};

/**
 * Toggles upvote on a complaint (relational database refactor).
 */
const toggleUpvote = async (dbUser, id) => {
  const complaint = await Complaint.findById(id);
  if (!complaint) return { error: 404, message: 'Complaint not found' };

  const userId = dbUser._id;
  const existingUpvote = await Upvote.findOneAndDelete({ complaintId: id, userId });

  let upvotes;
  if (existingUpvote) {
    const updated = await Complaint.findByIdAndUpdate(id, { $inc: { upvotes: -1 } }, { new: true });
    upvotes = updated.upvotes;
  } else {
    try {
      await Upvote.create({ complaintId: id, userId });
      const updated = await Complaint.findByIdAndUpdate(id, { $inc: { upvotes: 1 } }, { new: true });
      upvotes = updated.upvotes;
      createNotification({
        userId: updated.userId,
        complaintId: updated._id,
        type: 'upvote',
        message: 'Your complaint received a new upvote.',
      });
    } catch (_err) {
      upvotes = complaint.upvotes;
    }
  }

  return { data: { upvotes, hasUpvoted: !existingUpvote } };
};

/**
 * Aggregates statistics for the analytics dashboard.
 * Uses a single $facet stage to run all aggregations in one query — much faster.
 */
const getStats = async (dbUser, query = {}) => {
  const matchFilter = {};

  // Role-based scoping: department staff only see their own category
  if (dbUser.role === 'department_staff' && dbUser.department) {
    matchFilter.category = dbUser.department;
  } else if (query.dept && query.dept !== 'All') {
    matchFilter.category = query.dept;
  }

  // Time filter
  if (query.days && query.days !== 'all') {
    const daysAgo = new Date();
    daysAgo.setDate(daysAgo.getDate() - parseInt(query.days, 10));
    matchFilter.createdAt = { $gte: daysAgo };
  }

  // Urgency filter (for drill-down)
  if (query.urgency && query.urgency !== 'All') {
    matchFilter.urgency = query.urgency;
  }

  // Single facet pipeline — one round-trip to MongoDB
  const [result] = await Complaint.aggregate([
    { $match: matchFilter },
    {
      $facet: {
        // Overall KPI totals
        totals: [
          {
            $group: {
              _id: null,
              total:              { $sum: 1 },
              pending:            { $sum: { $cond: [{ $eq: ['$status', 'Pending'] },     1, 0] } },
              inProgress:         { $sum: { $cond: [{ $eq: ['$status', 'In Progress'] }, 1, 0] } },
              resolved:           { $sum: { $cond: [{ $eq: ['$status', 'Resolved'] },    1, 0] } },
              rejected:           { $sum: { $cond: [{ $eq: ['$status', 'Rejected'] },    1, 0] } },
              highUrgency:        { $sum: { $cond: [{ $eq: ['$urgency', 'High'] },       1, 0] } },
              pendingHighUrgency: {
                $sum: {
                  $cond: [{ $and: [{ $eq: ['$urgency', 'High'] }, { $eq: ['$status', 'Pending'] }] }, 1, 0]
                }
              },
              totalUpvotes: { $sum: '$upvotes' },
            },
          },
        ],

        // Complaints grouped by category/department
        byCategory: [
          {
            $group: {
              _id:      '$category',
              total:    { $sum: 1 },
              resolved: { $sum: { $cond: [{ $eq: ['$status', 'Resolved'] }, 1, 0] } },
              pending:  { $sum: { $cond: [{ $eq: ['$status', 'Pending'] },  1, 0] } },
              high:     { $sum: { $cond: [{ $eq: ['$urgency', 'High'] },    1, 0] } },
            },
          },
          { $sort: { total: -1 } },
        ],

        // Daily time series — all dates, not limited to 14 days
        byDay: [
          {
            $group: {
              _id:      { $dateToString: { format: '%Y-%m-%d', date: '$createdAt' } },
              count:    { $sum: 1 },
              resolved: { $sum: { $cond: [{ $eq: ['$status', 'Resolved'] }, 1, 0] } },
              pending:  { $sum: { $cond: [{ $eq: ['$status', 'Pending'] },  1, 0] } },
            },
          },
          { $sort: { _id: 1 } },
        ],

        // Complaints by urgency level
        byUrgency: [
          {
            $group: {
              _id:   '$urgency',
              count: { $sum: 1 },
            },
          },
          { $sort: { count: -1 } },
        ],

        // Complaints by day of week (Mon=1 ... Sun=7) for heatmap/bar
        byWeekday: [
          {
            $group: {
              _id:   { $isoDayOfWeek: '$createdAt' },
              count: { $sum: 1 },
            },
          },
          { $sort: { _id: 1 } },
        ],

        // Average resolution time for resolved complaints (in hours)
        resolutionTime: [
          {
            $match: { status: 'Resolved' },
          },
          {
            $project: {
              hoursToResolve: {
                $divide: [
                  { $subtract: ['$updatedAt', '$createdAt'] },
                  1000 * 60 * 60, // ms → hours
                ],
              },
            },
          },
          {
            $group: {
              _id: null,
              avgHours: { $avg: '$hoursToResolve' },
              minHours: { $min: '$hoursToResolve' },
              maxHours: { $max: '$hoursToResolve' },
            },
          },
        ],

        // High urgency pending, grouped by department
        highUrgencyByDept: [
          { $match: { urgency: 'High', status: 'Pending' } },
          { $group: { _id: '$category', count: { $sum: 1 } } },
          { $sort: { count: -1 } },
        ],
      },
    },
  ]);

  const totals = result.totals[0] || {
    total: 0, pending: 0, inProgress: 0, resolved: 0, rejected: 0,
    highUrgency: 0, pendingHighUrgency: 0, totalUpvotes: 0,
  };

  // Build byStatus for pie chart
  const byStatus = [
    { name: 'Pending',     value: totals.pending },
    { name: 'In Progress', value: totals.inProgress },
    { name: 'Resolved',    value: totals.resolved },
    { name: 'Rejected',    value: totals.rejected },
  ];

  // Weekday label mapping
  const WEEKDAY_NAMES = ['', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  const byWeekday = result.byWeekday.map(d => ({
    day: WEEKDAY_NAMES[d._id] || `Day ${d._id}`,
    count: d.count,
  }));

  const resolutionStats = result.resolutionTime[0] || { avgHours: 0, minHours: 0, maxHours: 0 };

  return {
    totals,
    byStatus,
    byCategory: result.byCategory,
    byDay:      result.byDay,
    byUrgency:  result.byUrgency,
    byWeekday,
    resolutionStats,
    highUrgencyByDept: result.highUrgencyByDept.map(x => ({ category: x._id, count: x.count })),
  };
};


/**
 * Returns lightweight complaint data for map viewport rendering.
 */
const getMapComplaints = async (dbUser, query) => {
  const { swLat, swLng, neLat, neLng } = query;

  let filter = scopeFilterForUser(dbUser, { status: { $ne: 'Resolved' } });

  if (swLat && swLng && neLat && neLng) {
    filter.location = {
      $geoWithin: {
        $box: [
          [parseFloat(swLng), parseFloat(swLat)],
          [parseFloat(neLng), parseFloat(neLat)],
        ],
      },
    };
  }

  const complaints = await Complaint.find(filter)
    .select('_id category status urgency location upvotes createdAt')
    .limit(500)
    .lean();

  return complaints;
};

/**
 * Performs a geospatial search for nearby complaints to prevent duplicates.
 */
const getNearbyComplaints = async (lat, lng, category, radiusMeters = 100) => {
  const MAX_RADIUS_METERS = 5000;
  const radiusClamped = Math.min(parseFloat(radiusMeters) || 100, MAX_RADIUS_METERS);
  return Complaint.aggregate([
    {
      $geoNear: {
        near: { type: 'Point', coordinates: [parseFloat(lng), parseFloat(lat)] },
        distanceField: 'distanceMeters',
        maxDistance: radiusClamped,
        query: { category, status: { $ne: 'Resolved' } },
        spherical: true,
      },
    },
    { $limit: 5 },
    { $project: { description: 1, status: 1, upvotes: 1, distanceMeters: 1, createdAt: 1 } },
  ]);
};

/**
 * Allows a citizen to withdraw their own pending complaint.
 */
const withdrawComplaint = async (dbUser, id) => {
  const complaint = await Complaint.findOne({ _id: id, userId: dbUser._id });
  if (!complaint) return { error: 404, message: 'Complaint not found.' };

  if (complaint.status !== 'Pending') {
    return { error: 409, message: 'Only Pending complaints can be withdrawn.' };
  }

  await complaint.deleteOne();
  return { success: true };
};

module.exports = {
  createComplaint,
  listComplaints,
  listMyComplaints,
  getComplaintById,
  updateComplaintStatus,
  toggleUpvote,
  getStats,
  getMapComplaints,
  getNearbyComplaints,
  withdrawComplaint,
};
