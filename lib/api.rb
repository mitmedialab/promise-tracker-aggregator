require 'sinatra'
require 'sinatra/config_file'
require 'mongo'
require 'mongo_mapper'
require 'pry'
require 'json/ext'

class Setting
  include MongoMapper::Document
  
  key :installation_id, Integer
end

class Reading
  include MongoMapper::Document

  key :user_installation_id, Integer
  key :survey_id, Integer
  key :sensorId, Integer
  key :sensorValue, Float
end

class Survey
  include MongoMapper::Document

  key :title, String
  key :code, Integer
  key :status, String
  key :start_date, Time
  key :inputs, Array

end

class Response
  include MongoMapper::Document

  key :survey_id, Integer
  key :answers, Array
end

class Selfie
  include MongoMapper::Document
end

class PTApi < Sinatra::Base
  register Sinatra::ConfigFile

  config_file File.dirname(__FILE__) + '/../config.yml'

  configure do
    set :public_folder, File.dirname(__FILE__) + '/../public/'
    enable :static, :logging

    MongoMapper.connection = Mongo::Connection.new('localhost', 27017)
    MongoMapper.database = 'pt-api'

    Setting.create({installation_id: 0}) if !Setting.first
  end

  before do
    headers 'Access-Control-Allow-Origin' => '*'
    content_type 'application/json'

    if request.post?
      error 401 unless env['HTTP_AUTHORIZATION'] == settings.access_key
    end
  end

  options '*' do
    response.headers['Allow'] = 'HEAD,GET,POST,PUT,DELETE,OPTIONS'
    response.headers['Access-Control-Allow-Origin'] = '*'
    response.headers['Access-Control-Allow-Headers'] = 'X-Requested-With, X-HTTP-Method-Override, Content-Type, Authorization, Accept, Cache-Control'
    200
  end

  get '/register' do
    setting = Setting.first()
    id = setting.installation_id

    id += 1
    setting.installation_id = id
    if setting.save
      {
        status: 'success',
        payload: {
          installation_id: id,
          device_id: ""
        }
      }.to_json
    end
  end

  get '/readings' do
    all_readings = Reading.all

    {
      status: 'success',
      payload: all_readings
    }.to_json
  end

  post '/readings' do
    readings = JSON.parse(request.body.read)["readings"]
    saved_readings = []

    readings.each do |reading|
      reading = Reading.create(reading)
      reading.save
      saved_readings.push(reading)
    end

    {
      status: 'success',
      payload: saved_readings
    }.to_json
  end

  get '/surveys/:code/readings' do
    survey = Survey.first(code: params[:code].to_i)

    if survey
      {
        status: 'success',
        payload: Reading.where(survey_id: survey.id).sort(:timestamp.desc)
      }.to_json
    else
      {
        status: 'error',
        error_code: 12,
        error_message: 'Survey not found'
      }.to_json
    end
  end

  get '/surveys' do
    surveys = Survey.all

    {
      status: 'success',
      payload: surveys
    }.to_json
  end

  post '/surveys/:status' do
    data = JSON.parse(request.body.read)
    survey = Survey.first(id: data['id'])

    if survey
      survey.set(data)
    else
      survey = Survey.create(data)
    end

    survey.reload
    survey.status = params[:status]
    survey.start_date = Time.now.midnight
    Response.destroy_all({survey_id: survey.id})

    if survey.save
      {
        status: 'success',
        payload: { id: survey.id, start_date: survey.start_date }
      }.to_json
    else
      {
        status: 'error',
        error_code: 13,
        error_message: 'Survey could not be saved because id is already taken'
      }.to_json
    end
  end

  get '/surveys/:code' do
    survey = Survey.first(code: params[:code].to_i)

    if survey
      {
        status: 'success',
        payload: survey
      }.to_json
    else
      {
        status: 'error',
        error_code: 12,
        error_message: 'Survey not found'
      }.to_json
    end
  end

  put '/surveys/:code/close' do
    survey = Survey.first(code: params[:code].to_i)
    
    if survey
      survey.status = 'closed'
      survey.save
      { 
        status: 'success',
        payload: { id: survey.id }
      }.to_json
    else 
      {
        status: 'error',
        error_code: 12,
        error_message: 'Survey not found'
      }.to_json
    end
  end

  get '/surveys/:code/responses' do
    survey = Survey.first(code: params[:code].to_i)

    if survey
      {
        status: 'success',
        payload: Response.where(survey_id: survey.id).sort(:timestamp.desc)
      }.to_json
    else
      {
        status: 'error',
        error_code: 12,
        error_message: 'Survey not found'
      }.to_json
    end
  end

  get '/surveys/:code/survey-with-responses' do
    survey = Survey.first(code: params[:code].to_i)

    if survey
      {
        status: 'success',
        payload: {
          survey: survey,
          responses: Response.where(survey_id: survey.id).sort(:timestamp.desc),
          readings: Reading.where(survey_id: survey.id).sort(:timestamp.desc)
        }
      }.to_json
    else
      {
        status: 'error',
        error_code: 12,
        error_message: 'Survey not found'
      }.to_json
    end
  end

  get '/responses' do
    {
      status: 'success',
      payload: Response.all
    }.to_json
  end

  post '/responses' do
    response_data = JSON.parse(params[:response])
    survey = Survey.first(_id: response_data['survey_id'].to_i)
    duplicate = Response.first(
      installation_id: response_data['installation_id'],
      timestamp: response_data['timestamp']
    )

    if survey && !duplicate
      if survey.status != 'closed'
        response = Response.create(response_data)
        {
          status: 'success',
          payload: {id: response.id}
        }.to_json
      else
        {
          status: 'error',
          error_code: 14,
          error_message: 'Response could not be posted because survey is closed'
        }.to_json
      end
    elsif duplicate
      {
        status: 'success',
        payload: {id: duplicate.id}
      }.to_json
    else
      {
        status: 'error',
        error_code: 12,
        error_message: 'Survey not found'
      }.to_json
    end
  end

  get '/selfies' do
    all_selfies = Selfie.all

    {
      status: 'success',
      payload: all_selfies
    }.to_json
  end

  post '/selfies' do
    selfie_data = JSON.parse(params[:selfie])
    selfie = Selfie.create(selfie_data)
    {
      status: 'success',
      payload: {id: response.id}
    }.to_json
  end

  post '/upload_image' do
    original_name = params[:file][:filename]
    filename = SecureRandom.urlsafe_base64
    filename = filename + original_name[original_name.rindex('.')..-1]
    file = params[:file][:tempfile]

    begin
      File.open(settings.public_folder + filename, 'wb') do |f|
        f.write(file.read)
        response = Response.find(params[:id])
        if response
          input = response[:answers].select {|input| input['id'] == params[:input_id].to_i}
          if input
            input[0]['value'] = "#{request.base_url}/#{filename}"
            if response.save
              {
                status: 'success',
                payload: {id: params[:id], input_id: params[:input_id]}
              }.to_json
            else
              {
                status: 'error',
                error_code: 16,
                error_message: 'File Upload: cannot update response object'
              }.to_json
            end
          else
            {
              status: 'error',
              error_code: 15,
              error_message: 'File Upload: cannot find the corresponding input'
            }.to_json 
          end
        else
          {
            status: 'error',
            error_code: 14,
            error_message: 'File Upload: cannot find the response'
          }.to_json
        end
      end # post: file.open
    rescue IOError => e
      return {
        status: 'error',
        error_code: 17,
        error_message: 'File open failed'
      }.to_json
    ensure
      file.close unless file == nil
    end # post: try catch file.open error
  end # post: upload_image

  post '/upload_seflie' do
    original_name = params[:file][:filename]
    filename = SecureRandom.urlsafe_base64
    filename = filename + original_name[original_name.rindex('.')..-1]
    file = params[:file][:tempfile]

    begin
      File.open(settings.public_folder + filename, 'wb') do |f|
        f.write(file.read)
        selfie = Selfie.find(params[:id])
        if selfie
          selfie['URI'] = "#{request.base_url}/#{filename}"
          if selfie.save
            {
              status: 'success',
              payload: {}
            }.to_json
          else
            {
              status: 'error',
              error_code: 16,
              error_message: 'File Upload: cannot update selfie object'
            }.to_json
          end
        end
      end # post: file.open
    rescue IOError => e
      return {
        status: 'error',
        error_code: 17,
        error_message: 'File open failed'
      }.to_json
    ensure
      file.close unless file == nil
    end # post: try catch file.open error
  end # post: upload_image
end