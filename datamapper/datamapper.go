package datamapper

import (
	"database/sql"
	"fmt"
	"log"
	"reflect"
	"strings"

	"github.com/richterrettich/jsonpatch"
)

type DataMapper struct {
	db *sql.DB
}

type Config struct {
	User     string
	Port     int
	Host     string
	Password string
	Ssl      bool
	Database string
}

func DefaultConfig() Config {
	return Config{
		User:     "postgres",
		Port:     5432,
		Host:     "localhost",
		Password: "",
		Ssl:      false,
		Database: "lecture",
	}
}

func (c Config) toString() string {
	connectionString := fmt.Sprintf("user=%s", c.User)
	if c.Database != "" {
		connectionString = fmt.Sprintf("%s dbname=%s", connectionString, c.Database)
	}
	if c.Password != "" {
		connectionString = fmt.Sprintf("%s password=%s", connectionString, c.Password)
	}
	connectionString = fmt.Sprintf("%s host=%s", connectionString, c.Host)
	connectionString = fmt.Sprintf("%s port=%d", connectionString, c.Port)
	if !c.Ssl {
		connectionString = fmt.Sprintf("%s sslmode=disable", connectionString)
	}
	return connectionString
}

func New(config Config) (*DataMapper, error) {
	db, err := sql.Open("postgres", config.toString())
	if err != nil {
		return nil, err
	}
	return &DataMapper{db}, nil
}

/*func rowToBytes(row *sql.Row) ([]byte, error) {
	var result = make([]byte, 0)
	err := row.Scan(result)
	return result, err
}*/
func (mapper *DataMapper) ApplyPatch(id, userId string, patch *jsonpatch.Patch, compiler jsonpatch.PatchCompiler) error {
	options := map[string]interface{}{
		"id":     id,
		"userId": userId,
	}
	commands, err := compiler.Compile(patch, options)
	if err != nil {
		return err
	}

	tx, err := mapper.db.Begin()
	log.Println("executing before functions...")
	for _, com := range commands.Commands {
		err = com.ExecuteBefore(tx)
		if err != nil {
			tx.Rollback()
			return err
		}
	}
	log.Println("executing main functions")
	for _, com := range commands.Commands {
		err = com.ExecuteMain(tx)
		if err != nil {
			tx.Rollback()
			return err
		}
	}
	log.Println("executing after functions")
	for _, com := range commands.Commands {
		err = com.ExecuteAfter(tx)
		if err != nil {
			tx.Rollback()
			return err
		}
	}
	log.Println("committing transaction")
	return tx.Commit()
}

func (t *DataMapper) queryIntoBytes(query string, params ...interface{}) ([]byte, error) {
	row, err := t.db.Query(query, params...)
	if err != nil {
		return nil, err
	}
	defer row.Close()
	var result = make([]byte, 0)
	for row.Next() {
		var tmp = make([]byte, 0)
		err = row.Scan(&tmp)
		if err != nil {
			return nil, err
		}
		result = append(result, tmp...)
	}
	return result, nil
}

//TODO duplicate function. Merge with jsonpatch.prepare
func prepare(stmt string, values ...interface{}) (string, []interface{}) {
	parametersString := ""
	var parameters = make([]interface{}, 0)
	currentIndex := 1
	for _, v := range values {
		val := reflect.ValueOf(v)
		if val.Kind() == reflect.Slice {
			for i := 0; i < val.Len(); i++ {
				inval := val.Index(i)
				parameters = append(parameters, inval.Interface())
				parametersString = fmt.Sprintf("%s,$%d", parametersString, currentIndex)
				currentIndex = currentIndex + 1
			}
		} else {
			parameters = append(parameters, v)
			parametersString = fmt.Sprintf("%s,$%d", parametersString, currentIndex)
			currentIndex = currentIndex + 1
		}
	}
	stmt = fmt.Sprintf(stmt, strings.Trim(parametersString, ","))
	return stmt, parameters
}
