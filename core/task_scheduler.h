/*
 * task_scheduler.h
 *
 *  Created on: Apr 10, 2017
 *      Author: alexeedm
 */

#include <string>
#include <vector>
#include <functional>
#include <list>
#include <queue>
#include <unordered_map>
#include <memory>

// TODO: remove empty tasks
class TaskScheduler
{
public:
	using TaskID = int;
	static const TaskID invalidTaskId = (TaskID) -1;

	TaskScheduler();

	TaskID createTask     (const std::string& label);
	TaskID getTaskId      (const std::string& label);
	TaskID getTaskIdOrDie (const std::string& label);

	void addTask(TaskID id, std::function<void(cudaStream_t)> task, int execEvery = 1);
	void addDependency(TaskID id, std::vector<TaskID> before, std::vector<TaskID> after);
	void setHighPriority(TaskID id);

	void compile();
	void run();

	void forceExec(TaskID id);

private:
	struct Node;
	struct Node
	{
		std::string label;
		std::vector< std::pair<std::function<void(cudaStream_t)>, int> > funcs;

		std::vector<TaskID> before, after;
		std::list<Node*> to, from, from_backup;

		int priority;
		std::queue<cudaStream_t>* streams;
	};

	std::vector< std::unique_ptr<Node> > nodes;

	// Ordered sets of parallel work
	std::queue<cudaStream_t> streamsLo, streamsHi;

	int cudaPriorityLow, cudaPriorityHigh;

	int nExecutions{0};

	TaskID freeTaskId{0};
	std::unordered_map<TaskID, Node*> taskId2node;
	std::unordered_map<std::string, TaskID> label2taskId;

	Node* getTask     (TaskID id);
	Node* getTaskOrDie(TaskID id);

	void removeEmptyNodes();
};
