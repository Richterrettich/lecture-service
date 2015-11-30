package patchcompiler

import (
	"github.com/ant0ine/go-urlrouter"
	"github.com/richterrettich/lecture-service/lecturepatch"
)

type ModulePatchCompiler struct {
}

func ForModules() PatchCompiler {
	return ModulePatchCompiler{}
}

func (compiler ModulePatchCompiler) Compile(id string, patch *lecturepatch.Patch) (*CommandList, error) {
	result := &CommandList{}
	router := &urlrouter.Router{
		Routes: []urlrouter.Route{
			urlrouter.Route{
				PathExp: "/recommendations",
				Dest:    CommandGenerator(generateAddRecommendation),
			},
			urlrouter.Route{
				PathExp: "/description",
				Dest:    CommandGenerator(generateReplaceDescription),
			},
			urlrouter.Route{
				PathExp: "/recommendations/:recommendationId",
				Dest:    CommandGenerator(generateRemoveRecommendation),
			},
			urlrouter.Route{
				PathExp: "/video",
				Dest:    CommandGenerator(generateAddVideo),
			},
			urlrouter.Route{
				PathExp: "/video/:videoId",
				Dest:    CommandGenerator(generateRemoveVideo),
			},
			urlrouter.Route{
				PathExp: "/script",
				Dest:    CommandGenerator(generateAddScript),
			},
			urlrouter.Route{
				PathExp: "/script/:scriptId",
				Dest:    CommandGenerator(generateRemoveScript),
			},
			urlrouter.Route{
				PathExp: "/exercises",
				Dest:    CommandGenerator(generateAddExercise),
			},
			urlrouter.Route{
				PathExp: "/exercises/:exerciseId",
				Dest:    CommandGenerator(generateRemoveExercise),
			},
		},
	}
	result.AddCommand(`SET TRANSACTION ISOLATION LEVEL SERIALIZABLE`)
	result.AddCommand(`SELECT check_version($1,$2,$3)`, id, "modules", patch.Version)
	err := router.Start()
	if err != nil {
		return nil, err
	}
	err = result.translatePatch(id, router, patch)
	if err != nil {
		return nil, err
	}
	result.AddCommand("SELECT increment_version($1,$2)", id, "modules")
	result.AddCommand(`REFRESH MATERIALIZED VIEW module_trees`)
	return result, nil
}

// database checked
func generateReplaceDescription(id string, op *lecturepatch.Operation, params map[string]string) (*command, error) {
	if op.Type != lecturepatch.REPLACE {
		return nil, InvalidPatchError{"Operation Not allowed here."}
	}
	return createCommand("SELECT replace_module_description($1,$2)", id, op.Value), nil
}

//database checked
func generateAddRecommendation(id string, op *lecturepatch.Operation, params map[string]string) (*command, error) {
	if op.Type != lecturepatch.ADD {
		return nil, InvalidPatchError{"Operation Not allowed here."}
	}
	return createCommand("SELECT add_module_recommendation($1,$2)", id, op.Value), nil
}

//database checked
func generateRemoveRecommendation(id string, op *lecturepatch.Operation, params map[string]string) (*command, error) {
	if op.Type != lecturepatch.REMOVE {
		return nil, InvalidPatchError{"Operation Not allowed here."}
	}
	return createCommand("SELECT remove_module_recommendation($1,$2)", id, params["recommendationId"]), nil
}

//database checked
func generateAddVideo(id string, op *lecturepatch.Operation, params map[string]string) (*command, error) {
	if op.Type != lecturepatch.ADD {
		return nil, InvalidPatchError{"Operation Not allowed here."}
	}
	return createCommand(`SELECT add_module_video($1,$2)`, id, op.Value), nil
}

// database checked
func generateRemoveVideo(id string, op *lecturepatch.Operation, params map[string]string) (*command, error) {
	if op.Type != lecturepatch.REMOVE {
		return nil, InvalidPatchError{"Operation Not allowed here."}
	}
	return createCommand(`SELECT remove_module_video($1,$2)`, id, params["videoId"]), nil
}

//database checked
func generateAddScript(id string, op *lecturepatch.Operation, params map[string]string) (*command, error) {
	if op.Type != lecturepatch.ADD {
		return nil, InvalidPatchError{"Operation Not allowed here."}
	}
	return createCommand(`SELECT add_module_script($1,$2)`, id, op.Value), nil
}

//dataase checked
func generateRemoveScript(id string, op *lecturepatch.Operation, params map[string]string) (*command, error) {
	if op.Type != lecturepatch.REMOVE {
		return nil, InvalidPatchError{"Operation Not allowed here."}
	}
	return createCommand(`SELECT remove_module_script($1,$2)`, id, params["scriptId"]), nil
}

//database checked
func generateAddExercise(id string, op *lecturepatch.Operation, params map[string]string) (*command, error) {
	if op.Type != lecturepatch.ADD {
		return nil, InvalidPatchError{"Operation Not allowed here."}
	}
	value := op.Value.(map[string]interface{})
	stmt, par := prepare("SELECT add_exercise(%v)", value["id"], id, value["backend"])
	return createCommand(stmt, par...), nil
}

//database checked
func generateRemoveExercise(id string, op *lecturepatch.Operation, params map[string]string) (*command, error) {
	if op.Type != lecturepatch.REMOVE {
		return nil, InvalidPatchError{"Operation Not allowed here."}
	}
	return createCommand("SELECT remove_exercise($1,$2)", id, params["exerciseId"]), nil
}
