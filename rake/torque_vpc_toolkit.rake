namespace :job do

	desc "Submit a job (requires: SCRIPT=<job_script_name>)"
	task :submit do

		script=ENV['SCRIPT']
		resources=ENV['RESOURCES']
		additional_attrs=ENV['ATTRIBUTES']

		configs=Util.load_configs
		group=ServerGroup.fetch(:source => "cache")
		configs["ssh_gateway_ip"]=group.vpn_gateway_ip
		configs.merge!(TorqueVPCToolkit.job_control_credentials(group.vpn_gateway_ip))

		xml=TorqueVPCToolkit.submit_job(configs, "jobs/#{script}", script, resources, additional_attrs)
		job_hash=TorqueVPCToolkit.jobs_list(xml)[0]
		TorqueVPCToolkit.print_job(job_hash)

	end

	desc "Submit all jobs (uses the jobs.json config file)"
	task :submit_all do

		configs=Util.load_configs
		group=ServerGroup.fetch(:source => "cache")
		configs["ssh_gateway_ip"]=group.vpn_gateway_ip
		configs.merge!(TorqueVPCToolkit.job_control_credentials(group.vpn_gateway_ip))
		xml=TorqueVPCToolkit.submit_all(configs)

	end

        desc "Submit job group (requires: JOB_GROUP=<file>)"
        task :submit_group do
		job_group=ENV['JOB_GROUP']

		configs=Util.load_configs
		group=ServerGroup.fetch(:source => "cache")
		configs["ssh_gateway_ip"]=group.vpn_gateway_ip
		configs.merge!(TorqueVPCToolkit.job_control_credentials(group.vpn_gateway_ip))

		xml=TorqueVPCToolkit.submit_all(configs, job_group)
        end

	desc "List jobs"
	task :list do

		configs=Util.load_configs
		group=ServerGroup.fetch(:source => "cache")
		configs.merge!(TorqueVPCToolkit.job_control_credentials(group.vpn_gateway_ip))
		xml=HttpUtil.get(
			"https://"+group.vpn_gateway_ip+"/jobs.xml",
			configs["torque_job_control_username"],
			configs["torque_job_control_password"]
		)
		jobs=TorqueVPCToolkit.jobs_list(xml)
		puts "Jobs:"
		jobs.each do |job|
			puts "\t#{job['id']}: #{job['description']} (#{job['status']})"
		end

	end

	desc "List node states"
	task :node_states do

		configs=Util.load_configs
		group=ServerGroup.fetch(:source => "cache")
		configs.merge!(TorqueVPCToolkit.job_control_credentials(group.vpn_gateway_ip))
		xml=HttpUtil.get(
			"https://"+group.vpn_gateway_ip+"/nodes",
			configs["torque_job_control_username"],
			configs["torque_job_control_password"]
		)
		node_states=TorqueVPCToolkit.node_states(xml)
		puts "Nodes:"
		node_states.each_pair do |name, state|
			puts "\t#{name}: #{state}"
		end

	end

	desc "Poll/loop until job controller is online"
	task :poll_controller do
		timeout=ENV['CONTROLLER_TIMEOUT']
		if timeout.nil? or timeout.empty? then
			timeout=1200
		end

		configs=Util.load_configs
		group=ServerGroup.fetch(:source => "cache")
		configs.merge!(TorqueVPCToolkit.job_control_credentials(group.vpn_gateway_ip))

		puts "Polling for job controller to come online (this may take a couple minutes)..."
		nodes=nil
		TorqueVPCToolkit.poll_until_online(group.vpn_gateway_ip, timeout, configs) do |nodes_hash|
			if nodes != nodes_hash then
				nodes = nodes_hash
				nodes_hash.each_pair do |name, state|
					puts "\t#{name}: #{state}"
				end
				puts "\t--"
			end
		end
		puts "Job controller online."
	end

	desc "Poll/loop until jobs finish"
	task :poll_jobs do
		timeout=ENV['JOBS_TIMEOUT']
		if timeout.nil? or timeout.empty? then
			timeout=3600
		end

		configs=Util.load_configs
		group=ServerGroup.fetch(:source => "cache")
		configs.merge!(TorqueVPCToolkit.job_control_credentials(group.vpn_gateway_ip))

		puts "Polling for jobs to finish running..."
		TorqueVPCToolkit.poll_until_jobs_finished(group.vpn_gateway_ip, timeout, configs)
		puts "Jobs finished."
	end

        desc "Poll/loop until a range of jobs finishes (requires: FROM_ID=<id>, TO_ID=<id>"
        task :poll_jobs_range do
                timeout=ENV['JOBS_TIMEOUT']
		if timeout.nil? or timeout.empty? then
			timeout=3600
		end

                from_id=ENV['FROM_ID']
                to_id=ENV['TO_ID']
	
                configs=Util.load_configs
		group=ServerGroup.fetch(:source => "cache")
                puts "Polling for jobs #{from_id}-#{to_id} to finish running..."
		TorqueVPCToolkit.poll_until_job_range_finished(group.vpn_gateway_ip,
            Integer(from_id), Integer(to_id), timeout, configs)
		puts "Jobs finished."

        end

        desc "Submit a job group and poll until it is complete (requires: JOB_GROUP=<file>)"
        task :submit_group_and_poll do
                configs=Util.load_configs
		group=ServerGroup.fetch(:source => "cache")

                initial_max = TorqueVPCToolkit.get_max_job_id(configs, group)
                Rake::Task['job:submit_group'].invoke
                new_max = TorqueVPCToolkit.get_max_job_id(configs, group)

                ENV['FROM_ID'] = "#{initial_max + 1}"
                ENV['TO_ID'] = "#{new_max}"
                Rake::Task['job:poll_jobs_range'].invoke                
        end

	desc "Print job logs for the specified JOB_ID."
	task :log do
		job_id=ENV['JOB_ID']

		configs=Util.load_configs
		group=ServerGroup.fetch(:source => "cache")
		configs.merge!(TorqueVPCToolkit.job_control_credentials(group.vpn_gateway_ip))
		job=TorqueVPCToolkit.job_hash(group.vpn_gateway_ip, job_id, configs)

		puts "--"
		puts "Job ID: #{job['id']}"
		puts "Description: #{job['description']}"
		puts "Status: #{job['status']}"
		puts "--"
		puts "Stdout:\n#{job['stdout']}"
		puts "--"
		puts "Stderr:\n#{job['stderr']}"

	end

end

desc "Poll the controller, sync data, submit and poll all jobs."
task :jobs do

	Rake::Task['job:poll_controller'].invoke
	Rake::Task['share:sync'].invoke
	Rake::Task['job:submit_all'].invoke
	Rake::Task['job:poll_jobs'].invoke
	cleanup=ENV['CLEANUP']

	if cleanup then
		Rake::Task['group:delete'].invoke
	end

end

desc "DEPRECATED"
task :all do

	puts "DEPRECATED: The 'all' task is deprecated. Use the 'rake create && rake jobs' tasks instead."
end
