namespace :markus do
  namespace :load do
    desc "Loads 'faked' results into database"
    task(results: :environment) do

      if ENV['short_id'].nil?
        $stderr.puts "Usage: rake load:results short_id=string\n\nNOTE: Assignment must not exist."
        exit(1)
      end

      puts "Loading results into database (this might take a long time)... "
      # set up assignments
      a1 = Assignment.new
      rule = PenaltyPeriodSubmissionRule.new
      a1.short_identifier = ENV['short_id']
      a1.description = "Conditionals and Loops"
      a1.message = "Learn to use conditional statements, and loops."
      a1.due_date = Time.now
      a1.group_min = 1
      a1.group_max = 1
      a1.student_form_groups = false
      a1.group_name_autogenerated = true
      a1.group_name_displayed = false
      a1.repository_folder = a1.short_identifier
      a1.submission_rule = rule
      a1.invalid_override = false
      a1.marking_scheme_type = Assignment::MARKING_SCHEME_TYPE[:rubric]
      a1.display_grader_names_to_students = false
      a1.build_assignment_stat
      a1.save!

      # load users
      STUDENT_CSV = File.expand_path(File.join(File.dirname(__FILE__), '..', '..', 'db', 'data', 'students.csv'))
      if File.readable?(STUDENT_CSV)
        csv_students = File.new(STUDENT_CSV)
        User.upload_user_list(Student, csv_students, nil)
      end

      # create groupings for each student in A1
      students = Student.all
      students.each do |student|
        begin
          student.create_group_for_working_alone_student(a1.id)
          grouping = student.accepted_grouping_for(a1.id)
          grouping.create_grouping_repository_folder
        rescue Exception => e
          puts "Caught exception on #{student.user_name}: #{e.message}" # ignore exceptions
        end
      end

      # create rubric criteria for a1
      rubric_criteria = [{rubric_criterion_name: "Uses Conditionals", weight: 1}, {rubric_criterion_name: "Code Clarity", weight: 2}, {rubric_criterion_name: "Code Is Documented", weight: 3}, {rubric_criterion_name: "Uses For Loop", weight: 1}]
      default_levels = {level_0_name: "Quite Poor", level_0_description: "This criterion was not satisifed whatsoever", level_1_name: "Satisfactory", level_1_description: "This criterion was satisfied", level_2_name: "Good", level_2_description: "This criterion was satisfied well", level_3_name: "Great", level_3_description: "This criterion was satisfied really well!", level_4_name: "Excellent", level_4_description: "This criterion was satisfied excellently"}
      rubric_criteria.each do |rubric_criteria|
        rc = RubricCriterion.new
        rc.update_attributes(rubric_criteria)
        rc.update_attributes(default_levels)
        rc.assignment = a1
        rc.save
      end

      # create submissions
      students.each do |student|
        if student.has_accepted_grouping_for?(a1.id)
          grouping = student.accepted_grouping_for(a1.id)
          group = grouping.group
          #commit some files into the group repository
          file_dir = File.join(File.dirname(__FILE__), '..', '..', 'db', 'sample_submission_files')
          Dir.foreach(file_dir) do |filename|
            unless File.directory?(File.join(file_dir, filename))
              file_contents = File.open(File.join(file_dir, filename))
              file_contents.rewind
              group.access_repo do |repo|
                txn = repo.get_transaction(student.user_name)
                path = File.join(a1.repository_folder, filename)
                txn.add(path, file_contents.read, '')
                repo.commit(txn)
              end
            end
          end
          submission = Submission.create_by_timestamp(grouping, Time.now)
          result = submission.get_latest_result
          # create marks for each criterion and attach to result
          a1.rubric_criteria.each do |criterion|
            # save a mark for each criterion
            m = Mark.new
            m.markable = criterion
            m.result = result
            m.mark = rand(5) # assign some random mark
            m.save
          end
          result.overall_comment = "Assignment goals pretty much met, but some things would need improvement. Other things are absolutely fantastic! Seriously, this is just some random text."
          result.marking_state = Result::MARKING_STATES[:complete]
          result.released_to_students = true
          result.save
        end
      end
  		# compute summary statistics for a1
  		a1.set_results_statistics
      puts "Done!"
    end
  end
end
