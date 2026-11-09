from pathlib import Path
p=Path('review_artifacts/m203_computer_classroom_20261107/sessions/computer_sessions.gd')
s=p.read_text()
s=s.replace('\t\t"editor":','''\t\t"rename":
			var source := Files.path(str(action.get("path","")))
			var target := Files.path(str(action.get("new_path","")))
			if source.is_empty() or target.is_empty() or not workspace.files.has(source) or workspace.files.has(target):
				_error(peer,"Choose an existing source and an unused valid destination.")
				return
			workspace.files[target]=workspace.files[source].duplicate(true)
			workspace.files[target].version+=1
			workspace.files.erase(source)
			if workspace.editor.get("path","")==source:workspace.editor.path=target
		"editor":''')
s=s.replace('packet.papers=[]\n\tfor paper in game.school.papers.values():\n\t\tif paper.owner==peer:packet.papers.append(paper.duplicate(true))','''packet.assignments=[]
	for paper in game.school.papers.values():
		if paper.owner!=peer:continue
		var safe: Dictionary=game.school._public_project(paper.project,not paper.mark.is_empty() or paper.lesson)
		packet.assignments.append({"id":paper.id,"title":str(safe.get("title","Assignment")),"questions":safe.get("questions",[]),"answers":paper.answers.duplicate(true),"mark":paper.mark.duplicate(true),"can_submit":paper.mark.is_empty() and game.school.activity.get("kind","")=="lecture"})
	packet.materials=[]
	if game.school.phase=="lesson":
		var stage: Dictionary=game.school.teaching_stage()
		packet.materials.append({"title":str(stage.get("title","Lesson")),"text":str(stage.get("text",stage.get("caption","")))})''')
# Refresh assignment view only when requested; school has its own authoritative updates.
s=s.replace('\t\t"answer", "submit":','\t\t"refresh":\n\t\t\tpass\n\t\t"answer", "submit":')
p.write_text(s)
