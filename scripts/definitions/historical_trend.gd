extends RefCounted
class_name HistoricalTrend
var start_date: String
var end_date: String
var daily_summaries: Array[DailySummary] = []
var trend_type: String  # "task_success", "guest_satisfaction", "failure_reasons", "area_performance"
var trend_data: Array[Dictionary] = []
var average_success_rate: float = 0.0
var average_guest_mood: float = 0.0
var improvement_percentage: float = 0.0
var declining_areas: Array[String] = []
var improving_areas: Array[String] = []

func _init(start: String, end: String) -> void:
	start_date = start
	end_date = end

func calculate_trends() -> void:
	if daily_summaries.size() == 0:
		return
	
	var success_sum: float = 0.0
	var mood_sum: float = 0.0
	
	for summary in daily_summaries:
		success_sum += summary.success_rate
		mood_sum += summary.average_guest_mood
	
	average_success_rate = success_sum / daily_summaries.size()
	average_guest_mood = mood_sum / daily_summaries.size()
	
	# Calculate improvement from first to last period
	if daily_summaries.size() > 1:
		var first: float = daily_summaries[0].success_rate
		var last: float = daily_summaries[-1].success_rate
		if first > 0:
			improvement_percentage = ((last - first) / first) * 100.0

func to_dict() -> Dictionary:
	var summaries_dict: Variant = []
	for summary in daily_summaries:
		summaries_dict.append(summary.to_dict())
	
	return {
		"start_date": start_date,
		"end_date": end_date,
		"trend_type": trend_type,
		"trend_data": trend_data,
		"average_success_rate": average_success_rate,
		"average_guest_mood": average_guest_mood,
		"improvement_percentage": improvement_percentage,
		"declining_areas": declining_areas,
		"improving_areas": improving_areas,
		"daily_summaries": summaries_dict
	}
